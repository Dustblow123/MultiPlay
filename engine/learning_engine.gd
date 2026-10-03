class_name LearningEngine
extends RefCounted
## Moteur d'apprentissage par répétition espacée (section 4 du document de
## conception). Couche de logique pure : aucune dépendance au graphisme.
##
## Le moteur choisit QUOI demander (`next_item`), reçoit chaque résultat
## (`report_result`) et tient l'état de chaque fait. Le jeu décide seulement
## COMMENT présenter l'item.
##
## Tout changement d'état découle d'une entrée du journal brut (4.9) : l'état
## complet peut être recalculé à partir du journal (`rebuild_from_journal`).

signal fact_state_changed(key: String, old_state: int, new_state: int)
signal fact_mastered(key: String)

const SAVE_VERSION := 1

const MODE_PRESENTATION := "presentation"
const MODE_QCM := "qcm"
const MODE_WHEEL := "wheel"
const MODE_DECOMPOSITION := "decomposition"

const MISSION_EXPLORATION := "exploration"
const MISSION_DEFENSE := "defense"
const MISSION_DUEL := "duel"
const MISSION_ARENA := "arena"
const MISSION_BOSS := "boss"

var config: EngineConfig
var rng := RandomNumberGenerator.new()
## Clé canonique -> FactState.
var states: Dictionary = {}
## Journal brut : toutes les réponses et les débuts de session (4.9).
var journal: Array = []
var session_id: int = 0
var current_day: int = 0
var session_active: bool = false
## Temps de réponse récents sur les faits triviaux, par mode (4.4).
var calibration: Dictionary = {"qcm": [], "wheel": [], "decomposition": []}

# --- État de la session en cours (non persisté) ---
var _queue: Array = []
var _served: Array = []
var _asks_this_session: Dictionary = {}
var _consecutive_errors: int = 0
var _item_counter: int = 0
var _due_count_at_start: int = 0
var _planned_new: Array = []
var _planned_reviews: Array = []
var _session_stats: Dictionary = {}


func _init(cfg: EngineConfig = null, seed: int = -1) -> void:
	config = cfg if cfg != null else EngineConfig.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	_build_facts()


func _build_facts() -> void:
	states.clear()
	var lo := 0 if config.include_zero else config.table_min
	for x in range(lo, config.table_max + 1):
		for y in range(x, config.table_max + 1):
			var f := Fact.make(x, y)
			states[f.key] = FactState.new(f)


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

## Ouvre une session de jeu pour le jour `day` (nombre de jours depuis l'époque).
## Compose la file d'items (4.7) et retourne un résumé.
func start_session(day: int) -> Dictionary:
	if session_active:
		end_session()
	session_id += 1
	current_day = day
	session_active = true
	_queue = []
	_served = []
	_asks_this_session = {}
	_consecutive_errors = 0
	_item_counter = 0
	_session_stats = {"items": 0, "correct": 0, "errors": 0, "fast": 0, "suspicious": 0,
		"mastered": [], "relapsed": [], "new_facts": [], "stardust": 0}
	journal.append({"type": "session_start", "session": session_id, "day": day, "t": _now()})
	_compose_queue()
	return {
		"session": session_id,
		"day": day,
		"due": _due_count_at_start,
		"planned_reviews": _planned_reviews.duplicate(),
		"planned_new": _planned_new.duplicate(),
		"queue_size": _queue.size(),
	}


## Clôt la session et retourne ses statistiques.
func end_session() -> Dictionary:
	session_active = false
	var stats := _session_stats.duplicate(true)
	stats["session"] = session_id
	return stats


func session_stats() -> Dictionary:
	return _session_stats.duplicate(true)


func _compose_queue() -> void:
	var due := due_reviews()
	_due_count_at_start = due.size()
	var reviews := due.slice(0, mini(due.size(), config.max_reviews_per_session))
	_planned_reviews = []
	for fs in reviews:
		_planned_reviews.append(fs.key)

	var n_new := allowed_new_facts_count(due.size())
	_planned_new = pick_new_facts(n_new)
	var warmup := _pick_warmup(config.warmup_trivial_facts)

	var queue: Array = []
	queue.append_array(warmup)
	var reviews_mixed := _planned_reviews.duplicate()
	_shuffle(reviews_mixed)
	if _planned_new.is_empty():
		queue.append_array(reviews_mixed)
	else:
		var step := maxi(1, int(ceil(reviews_mixed.size() / float(_planned_new.size() + 1))))
		var ri := 0
		var ni := 0
		while ri < reviews_mixed.size() or ni < _planned_new.size():
			for _i in range(step):
				if ri < reviews_mixed.size():
					queue.append(reviews_mixed[ri])
					ri += 1
			if ni < _planned_new.size():
				queue.append(_planned_new[ni])
				ni += 1

	var target := config.items_per_session - _planned_new.size()
	if queue.size() < target:
		var fill := _practice_candidates(target - queue.size(), queue)
		queue.append_array(fill)
	_queue = _without_adjacent_duplicates(queue)


## Révisions dues (4.6), triées par retard relatif décroissant.
func due_reviews() -> Array:
	var due: Array = []
	for fs in states.values():
		if is_due(fs):
			due.append(fs)
	due.sort_custom(func(x: FactState, y: FactState) -> bool:
		var lx := lateness(x)
		var ly := lateness(y)
		if lx == ly:
			return x.key < y.key
		return lx > ly)
	return due


func is_due(fs: FactState) -> bool:
	if fs.state == FactState.State.NEW:
		return false
	return session_id >= fs.due_session and current_day >= fs.due_day


## Retard relatif : combien d'intervalles de retard (jours ou sessions).
func lateness(fs: FactState) -> float:
	var ld := (current_day - fs.due_day) / float(maxi(1, fs.interval_days))
	var ls := (session_id - fs.due_session) / float(maxi(1, fs.interval_sessions))
	return maxf(ld, ls)


## Une planète est « assiégée » quand une révision est en retard d'au moins un intervalle.
func is_besieged(fs: FactState) -> bool:
	return is_due(fs) and lateness(fs) >= 1.0


## Nombre de faits nouveaux (non triviaux) autorisés pour la session (4.7).
func allowed_new_facts_count(pending_reviews: int) -> int:
	if pending_reviews > config.new_facts_pending_reviews_limit:
		return 0
	if recent_error_rate() >= config.new_facts_error_rate_limit:
		return 0
	var remaining := 0
	for fs in states.values():
		if fs.state == FactState.State.NEW and not fs.fact.is_trivial():
			remaining += 1
	var n := rng.randi_range(config.min_new_facts_per_session, config.max_new_facts_per_session)
	return mini(n, remaining)


## Taux d'erreur sur les dernières réponses du journal (hors présentations).
func recent_error_rate() -> float:
	var n := 0
	var errors := 0
	for i in range(journal.size() - 1, -1, -1):
		var e: Dictionary = journal[i]
		if e.get("type", "") != "result" or e.get("mode", "") == MODE_PRESENTATION:
			continue
		if e.get("suspicious", false):
			continue
		n += 1
		if not e.get("correct", false):
			errors += 1
		if n >= config.error_rate_window:
			break
	return 0.0 if n == 0 else float(errors) / float(n)


## Faits nouveaux non triviaux, dans l'ordre de découverte des tables (5.2).
func pick_new_facts(n: int, tables: Array = []) -> Array:
	if n <= 0:
		return []
	var candidates: Array = []
	for fs in states.values():
		if fs.state != FactState.State.NEW or fs.fact.is_trivial():
			continue
		if not tables.is_empty() and not _belongs_to_any(fs.fact, tables):
			continue
		candidates.append(fs)
	candidates.sort_custom(func(x: FactState, y: FactState) -> bool:
		var rx := _fact_rank(x.fact)
		var ry := _fact_rank(y.fact)
		if rx[0] != ry[0]:
			return rx[0] < ry[0]
		if rx[1] != ry[1]:
			return rx[1] < ry[1]
		return x.key < y.key)
	var keys: Array = []
	for fs in candidates.slice(0, mini(n, candidates.size())):
		keys.append(fs.key)
	return keys


func _fact_rank(f: Fact) -> Array:
	var ra := config.table_order.find(f.a)
	var rb := config.table_order.find(f.b)
	if ra == -1:
		ra = 99
	if rb == -1:
		rb = 99
	return [mini(ra, rb), maxi(ra, rb)]


## Échauffement : faits triviaux, les non maîtrisés d'abord, puis les moins récents.
func _pick_warmup(n: int) -> Array:
	var trivial: Array = []
	for fs in states.values():
		if fs.fact.is_trivial():
			trivial.append(fs)
	trivial.sort_custom(func(x: FactState, y: FactState) -> bool:
		if x.state != y.state:
			return x.state < y.state
		if x.last_session != y.last_session:
			return x.last_session < y.last_session
		var rx := _fact_rank(x.fact)
		var ry := _fact_rank(y.fact)
		if rx[0] != ry[0]:
			return rx[0] < ry[0]
		return x.key < y.key)
	var keys: Array = []
	for fs in trivial.slice(0, mini(n, trivial.size())):
		keys.append(fs.key)
	return keys


## Items d'entraînement pour compléter une session : faits en cours (les plus
## proches de leur échéance), puis faits maîtrisés les moins récents, puis triviaux.
func _practice_candidates(n: int, exclude: Array, tables: Array = []) -> Array:
	if n <= 0:
		return []
	var in_progress: Array = []
	var mastered: Array = []
	var trivial: Array = []
	for fs in states.values():
		if exclude.has(fs.key) or fs.state == FactState.State.NEW:
			continue
		if not tables.is_empty() and not _belongs_to_any(fs.fact, tables):
			continue
		if _asks_this_session.get(fs.key, 0) >= config.max_asks_per_fact_per_session:
			continue
		if fs.fact.is_trivial():
			trivial.append(fs)
		elif fs.state == FactState.State.MASTERED:
			mastered.append(fs)
		else:
			in_progress.append(fs)
	# Les faits pas encore demandés dans la session d'abord, puis les moins récents.
	var by_asks := func(x: FactState, y: FactState) -> bool:
		var ax: int = _asks_this_session.get(x.key, 0)
		var ay: int = _asks_this_session.get(y.key, 0)
		if ax != ay:
			return ax < ay
		if x.last_session != y.last_session:
			return x.last_session < y.last_session
		return x.key < y.key
	_shuffle(in_progress)
	_shuffle(mastered)
	in_progress.sort_custom(by_asks)
	mastered.sort_custom(by_asks)
	trivial.sort_custom(by_asks)
	var pool: Array = []
	# Ratio connu/nouveau autour de 80/20 : on alterne faits en cours et maîtrisés.
	while pool.size() < n and (not in_progress.is_empty() or not mastered.is_empty()):
		if not in_progress.is_empty():
			pool.append(in_progress.pop_front().key)
		if pool.size() < n and not mastered.is_empty():
			pool.append(mastered.pop_front().key)
	for fs in trivial:
		if pool.size() >= n:
			break
		pool.append(fs.key)
	return pool


# ---------------------------------------------------------------------------
# Prochain calcul (4.10)
# ---------------------------------------------------------------------------

## Retourne le prochain item : fait, orientation, mode, distracteurs et temps cible.
## `context` est optionnel : {"type": "defense"|"exploration"|"duel"|"arena"|"boss",
## "tables": [7], "pair": ["7x8", "6x9"], "mode_hint": "decomposition"}.
func next_item(context: Dictionary = {}) -> Dictionary:
	assert(session_active, "start_session() doit être appelé avant next_item()")
	var key := _select_key(context)
	var fs: FactState = states[key]
	_asks_this_session[key] = _asks_this_session.get(key, 0) + 1
	var mode := _mode_for(fs, context)
	var orientation := _pick_orientation(fs)
	var first: int = orientation[0]
	var second: int = orientation[1]
	var product := fs.fact.product()
	_item_counter += 1
	var item := {
		"id": _item_counter,
		"session": session_id,
		"fact": key,
		"a": first,
		"b": second,
		"orientation": Fact.orientation_key(first, second),
		"question": "%d × %d" % [first, second],
		"answer": product,
		"accepted": [product],
		"mode": mode,
		"options": [],
		"target_time_ms": target_time_ms(mode),
		"state": fs.state_name(),
		"box": fs.box,
		"is_new": fs.state == FactState.State.NEW,
		"is_due": is_due(fs),
		"is_trivial": fs.fact.is_trivial(),
		"context": context.duplicate(true),
	}
	if mode == MODE_QCM:
		var options := Distractors.generate(fs.fact, 3, fs.confusions_by_frequency(), rng)
		options.append(product)
		_shuffle(options)
		item["options"] = options
	elif mode == MODE_DECOMPOSITION:
		item["question"] = str(product)
		item["accepted"] = [fs.fact.a] if fs.fact.a == fs.fact.b else [fs.fact.a, fs.fact.b]
		item["answer"] = fs.fact.a
	_served.append(key)
	return item


func _select_key(context: Dictionary) -> String:
	var type: String = context.get("type", "")
	var tables: Array = context.get("tables", [])
	var last_key: String = _served[-1] if not _served.is_empty() else ""

	# Le jeu peut imposer un fait précis (point faible d'un boss, tests).
	if context.has("fact") and states.has(context["fact"]):
		return context["fact"]

	# Anti-frustration (4.7) : après 2 erreurs consécutives, un fait facile et maîtrisé.
	if _consecutive_errors >= config.frustration_consecutive_errors:
		var easy := _pick_easy_key(last_key)
		if easy != "":
			_consecutive_errors = 0
			return easy

	match type:
		MISSION_ARENA:
			var k := _pick_mastered_key(tables, last_key)
			if k != "":
				return k
		MISSION_BOSS:
			var k := _pick_mastered_key(tables, last_key)
			if k != "":
				return k
		MISSION_DUEL:
			# Entraînement par contraste, puis retour à la file normale : le
			# Confondeur reste un adversaire spécial, pas toute la mission.
			var pair: Array = context.get("pair", [])
			if pair.size() == 2 and states.has(pair[0]) and states.has(pair[1]):
				var k: String = pair[1] if last_key == pair[0] else pair[0]
				if _asks_this_session.get(k, 0) < config.max_asks_per_fact_per_session:
					return k

	# File planifiée. Défense : révisions dues d'abord ; exploration : faits nouveaux d'abord.
	var index := _queue_pick_index(type, tables, last_key)
	if index >= 0:
		var key: String = _queue[index]
		_queue.remove_at(index)
		return key
	return _filler_key(tables, last_key)


func _queue_pick_index(type: String, tables: Array, last_key: String) -> int:
	var fallback := -1
	for i in range(_queue.size()):
		var k: String = _queue[i]
		if k == last_key:
			continue
		var fs: FactState = states[k]
		if _asks_this_session.get(k, 0) >= config.max_asks_per_fact_per_session:
			continue
		if not tables.is_empty() and not _belongs_to_any(fs.fact, tables):
			continue
		if fallback == -1:
			fallback = i
		match type:
			MISSION_DEFENSE:
				if is_due(fs) and fs.state != FactState.State.NEW:
					return i
			MISSION_EXPLORATION:
				if fs.state == FactState.State.NEW or fs.state == FactState.State.LEARNING:
					return i
			_:
				return i
	return fallback


func _filler_key(tables: Array, last_key: String) -> String:
	var pool := _practice_candidates(3, [last_key], tables)
	if not pool.is_empty():
		return pool[0]
	# Rien d'autre : faits nouveaux (profil vierge) puis le fait le moins demandé.
	var fresh := pick_new_facts(1, tables)
	if not fresh.is_empty() and fresh[0] != last_key:
		return fresh[0]
	var best := ""
	var best_asks := 1 << 30
	for fs in states.values():
		if fs.key == last_key:
			continue
		if not tables.is_empty() and not _belongs_to_any(fs.fact, tables):
			continue
		var asks: int = _asks_this_session.get(fs.key, 0)
		if asks < best_asks:
			best_asks = asks
			best = fs.key
	if best == "":
		best = states.keys()[0]
	return best


func _pick_easy_key(last_key: String) -> String:
	var candidates: Array = []
	for fs in states.values():
		if fs.key == last_key:
			continue
		if fs.state == FactState.State.MASTERED or (fs.fact.is_trivial() and fs.state != FactState.State.NEW):
			candidates.append(fs)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(x: FactState, y: FactState) -> bool:
		# Les plus sûrs d'abord : maîtrisés sans erreur récente, puis les moins récents.
		var ex := x.recent_error_rate()
		var ey := y.recent_error_rate()
		if ex != ey:
			return ex < ey
		if x.last_session != y.last_session:
			return x.last_session < y.last_session
		return x.key < y.key)
	return candidates[0].key


func _pick_mastered_key(tables: Array, last_key: String) -> String:
	var candidates: Array = []
	for fs in states.values():
		if fs.state != FactState.State.MASTERED or fs.key == last_key:
			continue
		if not tables.is_empty() and not _belongs_to_any(fs.fact, tables):
			continue
		candidates.append(fs)
	if candidates.is_empty():
		return ""
	_shuffle(candidates)
	return candidates[0].key


func _mode_for(fs: FactState, context: Dictionary) -> String:
	var hint: String = context.get("mode_hint", "")
	match fs.state:
		FactState.State.NEW:
			# Les faits triviaux passent directement au QCM (échauffement).
			return MODE_QCM if fs.fact.is_trivial() else MODE_PRESENTATION
		FactState.State.LEARNING:
			return MODE_QCM
		FactState.State.CONSOLIDATION:
			return MODE_QCM if hint == MODE_QCM else MODE_WHEEL
		_:
			if hint == MODE_DECOMPOSITION:
				return MODE_DECOMPOSITION
			if hint == MODE_QCM:
				return MODE_QCM
			return MODE_WHEEL


## Orientation (4.1) : si les statistiques divergent, la plus faible est présentée plus souvent.
func _pick_orientation(fs: FactState) -> Array:
	var orientations := fs.fact.orientations()
	if orientations.size() == 1:
		return orientations[0]
	var weak := _weak_orientation(fs)
	if weak != "" and rng.randf() < config.weak_orientation_bias:
		return orientations[0] if Fact.orientation_key(orientations[0][0], orientations[0][1]) == weak else orientations[1]
	return orientations[rng.randi_range(0, 1)]


func _weak_orientation(fs: FactState) -> String:
	var keys := fs.orientation_stats.keys()
	if keys.size() < 2:
		# Une orientation jamais vue est « faible » par défaut.
		if keys.size() == 1 and fs.orientation_stats[keys[0]]["attempts"] >= 2:
			var o := fs.fact.orientations()
			var seen: String = keys[0]
			for pair in o:
				var k := Fact.orientation_key(pair[0], pair[1])
				if k != seen:
					return k
		return ""
	var s0: Dictionary = fs.orientation_stats[keys[0]]
	var s1: Dictionary = fs.orientation_stats[keys[1]]
	if s0["attempts"] < 2 or s1["attempts"] < 2:
		return ""
	var acc0 := float(s0["correct"]) / float(s0["attempts"])
	var acc1 := float(s1["correct"]) / float(s1["attempts"])
	if absf(acc0 - acc1) >= config.orientation_divergence_rate:
		return keys[0] if acc0 < acc1 else keys[1]
	var t0 := FactState.median(s0["times"])
	var t1 := FactState.median(s1["times"])
	if t0 > 0 and t1 > 0 and absi(t0 - t1) >= config.orientation_divergence_ms:
		return keys[0] if t0 > t1 else keys[1]
	return ""


# ---------------------------------------------------------------------------
# Résultat (4.10)
# ---------------------------------------------------------------------------

## Le jeu renvoie la réponse donnée et le temps en millisecondes.
## `flags` optionnel : {"mashing": true} si un mitraillage de boutons a été détecté,
## {"variant": "inverted"} pour journaliser la présentation choisie par le jeu.
## Retourne l'issue : correct, fast, suspicious, old_state, new_state, box…
func report_result(item: Dictionary, given_answer: int, time_ms: int, flags: Dictionary = {}) -> Dictionary:
	assert(session_active, "start_session() doit être appelé avant report_result()")
	var key: String = item["fact"]
	var fs: FactState = states[key]
	var mode: String = item["mode"]
	var correct: bool = mode == MODE_PRESENTATION or item["accepted"].has(given_answer)
	var suspicious: bool = mode == MODE_QCM and (time_ms < config.anti_random_ms or flags.get("mashing", false))
	var fast: bool = correct and not suspicious and mode != MODE_PRESENTATION and time_ms <= int(item["target_time_ms"])
	var entry := {
		"type": "result",
		"t": _now(),
		"session": session_id,
		"day": current_day,
		"fact": key,
		"orientation": item["orientation"],
		"mode": mode,
		"options": item.get("options", []).duplicate(),
		"given": given_answer,
		"correct": correct,
		"fast": fast,
		"suspicious": suspicious,
		"time_ms": time_ms,
		"target_time_ms": item["target_time_ms"],
		"due": item.get("is_due", false),
		"context": item.get("context", {}).get("type", ""),
		"variant": str(flags.get("variant", "")),
	}
	journal.append(entry)
	var outcome := _ingest_entry(fs, entry)

	# Dynamique de session.
	_session_stats["items"] += 1
	if mode != MODE_PRESENTATION:
		if suspicious:
			_session_stats["suspicious"] += 1
		elif correct:
			_session_stats["correct"] += 1
			_session_stats["stardust"] += 1
			_consecutive_errors = 0
			if fast:
				_session_stats["fast"] += 1
		else:
			_session_stats["errors"] += 1
			_consecutive_errors += 1
	else:
		_session_stats["new_facts"].append(key)
	if outcome["mastered_now"]:
		_session_stats["mastered"].append(key)
	if outcome["relapse"]:
		_session_stats["relapsed"].append(key)
	if not correct or mode == MODE_PRESENTATION:
		_schedule_reinsert(key)
	outcome["stardust"] = 1 if (correct and not suspicious and mode != MODE_PRESENTATION) else 0
	return outcome


## Applique une entrée du journal à l'état du fait et à la calibration.
## Pure : ne dépend que de l'entrée et de l'état courant (rejouable).
func _ingest_entry(fs: FactState, e: Dictionary) -> Dictionary:
	var old_state: int = fs.state
	var mode: String = e["mode"]
	var correct: bool = e["correct"]
	var fast: bool = e["fast"]
	var suspicious: bool = e["suspicious"]
	var session: int = e["session"]
	var day: int = e["day"]
	var outcome := {"correct": correct, "fast": fast, "suspicious": suspicious,
		"old_state": old_state, "new_state": old_state, "box": fs.box,
		"mastered_now": false, "relapse": false, "state_changed": false}

	fs.last_session = session
	fs.last_day = day

	if mode == MODE_PRESENTATION:
		if fs.state == FactState.State.NEW:
			fs.state = FactState.State.LEARNING
			fs.box = 1
		fs.record_history({"correct": true, "time_ms": 0, "mode": mode,
			"orientation": e["orientation"], "session": session, "fast": false}, config.history_size)
		_schedule(fs, session, day)
		return _finish_outcome(fs, outcome, old_state)

	if suspicious:
		# Anti-hasard (4.5) : enregistré, mais ne fait pas progresser.
		fs.record_history({"correct": correct, "time_ms": e["time_ms"], "mode": mode,
			"orientation": e["orientation"], "session": session, "fast": false}, config.history_size)
		return _finish_outcome(fs, outcome, old_state)

	fs.total_attempts += 1
	var ostat := fs.orientation_stat(e["orientation"])
	ostat["attempts"] += 1
	if correct:
		ostat["correct"] += 1
		ostat["times"].append(int(e["time_ms"]))
		while ostat["times"].size() > config.history_size:
			ostat["times"].pop_front()
	fs.record_history({"correct": correct, "time_ms": e["time_ms"], "mode": mode,
		"orientation": e["orientation"], "session": session, "fast": fast}, config.history_size)

	var was_new := fs.state == FactState.State.NEW
	var due: bool = e.get("due", false)
	if correct:
		fs.total_correct += 1
		if was_new:
			fs.state = FactState.State.LEARNING
			fs.box = 1
		# Juste et rapide : +1 boîte (seulement lors d'une révision due, pour respecter l'espacement).
		if fast and due:
			fs.box = mini(fs.box + 1, config.box_max)
		if mode == MODE_QCM:
			fs.qcm_streak += 1
			if not fs.qcm_streak_sessions.has(session):
				fs.qcm_streak_sessions.append(session)
		elif fast:
			fs.wheel_fast_streak += 1
		if fs.state == FactState.State.LEARNING \
				and fs.qcm_streak >= config.qcm_successes_for_consolidation \
				and fs.qcm_streak_sessions.size() >= config.qcm_sessions_for_consolidation:
			fs.state = FactState.State.CONSOLIDATION
			fs.wheel_fast_streak = 0
		elif fs.state == FactState.State.CONSOLIDATION and fs.box >= config.mastery_box \
				and fast and mode != MODE_QCM and fs.wheel_fast_streak >= config.wheel_fast_successes_for_mastery:
			fs.state = FactState.State.MASTERED
			outcome["mastered_now"] = true
	else:
		if fs.state == FactState.State.MASTERED:
			fs.relapses += 1
			fs.state = FactState.State.CONSOLIDATION
			outcome["relapse"] = true
		fs.box = 1
		fs.qcm_streak = 0
		fs.qcm_streak_sessions = []
		fs.wheel_fast_streak = 0
		var given: int = int(e["given"])
		if given >= 0:
			var k := str(given)
			fs.confusions[k] = int(fs.confusions.get(k, 0)) + 1
	# Une réponse d'entraînement (fait non dû) ne déplace pas la révision
	# planifiée ; seules les erreurs, les révisions dues et les premières
	# rencontres programment une échéance.
	if not correct or due or was_new:
		_schedule(fs, session, day)

	# Calibration du temps moteur sur les faits triviaux (4.4).
	if correct and fs.fact.is_trivial() and calibration.has(mode):
		var samples: Array = calibration[mode]
		samples.append(int(e["time_ms"]))
		while samples.size() > config.calibration_window:
			samples.pop_front()
	return _finish_outcome(fs, outcome, old_state)


func _finish_outcome(fs: FactState, outcome: Dictionary, old_state: int) -> Dictionary:
	outcome["new_state"] = fs.state
	outcome["box"] = fs.box
	outcome["state_changed"] = fs.state != old_state
	if outcome["state_changed"]:
		fact_state_changed.emit(fs.key, old_state, fs.state)
		if fs.state == FactState.State.MASTERED:
			fact_mastered.emit(fs.key)
	return outcome


## Programme la prochaine révision selon la boîte (4.6).
func _schedule(fs: FactState, session: int, day: int) -> void:
	var b := clampi(fs.box, 0, config.box_max)
	var s_min: int = config.min_sessions_per_box[b]
	var d_min: int = config.min_days_per_box[b]
	if b >= 2 and fs.relapses > 0:
		d_min = maxi(1, int(round(d_min * pow(config.relapse_interval_factor, fs.relapses))))
	fs.interval_sessions = s_min
	fs.interval_days = d_min
	fs.due_session = session + s_min
	fs.due_day = day + d_min


## Re-présentation 2 ou 3 calculs plus tard dans la même session (4.5).
func _schedule_reinsert(key: String) -> void:
	var index := rng.randi_range(config.reinsert_after_min, config.reinsert_after_max)
	index = mini(index, _queue.size())
	# Jamais deux fois le même fait d'affilée.
	if index == 0:
		index = 1 if not _queue.is_empty() else 0
	_queue.insert(index, key)


# ---------------------------------------------------------------------------
# Seuil de rapidité (4.4)
# ---------------------------------------------------------------------------

func motor_base_ms(mode: String) -> int:
	var samples: Array = calibration.get(mode, [])
	if samples.size() >= config.calibration_min_samples:
		return FactState.median(samples)
	return int(config.default_motor_base_ms.get(mode, config.default_motor_base_ms["qcm"]))


func target_time_ms(mode: String) -> int:
	if mode == MODE_PRESENTATION:
		return 0
	return motor_base_ms(mode) + config.speed_margin_ms


# ---------------------------------------------------------------------------
# Lecture de l'état (hub, carte galactique, écran parent)
# ---------------------------------------------------------------------------

func fact_state(key: String) -> FactState:
	return states.get(key)


func counts_by_state() -> Dictionary:
	var counts := {"new": 0, "learning": 0, "consolidation": 0, "mastered": 0}
	for fs in states.values():
		counts[fs.state_name()] += 1
	return counts


## Carte galactique (5.1) : chaque table est un système, chaque fait une planète.
## Statuts : "dark" (jamais vu), "orbit" (en cours), "colonized" (maîtrisé),
## "besieged" (révision très en retard). `due` indique une attaque de pirates.
func galaxy_map() -> Dictionary:
	var map := {}
	var lo := 0 if config.include_zero else config.table_min
	for table in range(lo, config.table_max + 1):
		var facts := {}
		var colonized := 0
		var due := 0
		for other in range(lo, config.table_max + 1):
			var key := Fact.key_of(table, other)
			if not states.has(key):
				continue
			var fs: FactState = states[key]
			var status := planet_status(fs)
			facts[key] = {"status": status, "due": is_due(fs), "state": fs.state_name(), "box": fs.box}
			if fs.state == FactState.State.MASTERED:
				colonized += 1
			if is_due(fs):
				due += 1
		map[table] = {"facts": facts, "colonized": colonized, "total": facts.size(),
			"complete": colonized == facts.size(), "due": due}
	return map


func planet_status(fs: FactState) -> String:
	match fs.state:
		FactState.State.NEW:
			return "dark"
		FactState.State.MASTERED:
			return "besieged" if is_besieged(fs) else "colonized"
		_:
			return "orbit"


## Un système entièrement colonisé déclenche son boss (5.1, 7).
func boss_ready(table: int) -> bool:
	for fs in states.values():
		if fs.fact.belongs_to(table) and fs.state != FactState.State.MASTERED:
			return false
	return true


## Faits qui posent problème : erreurs récentes ou confusion fréquente (10.1).
func problem_facts() -> Array:
	var out: Array = []
	for fs in states.values():
		if fs.state == FactState.State.NEW:
			continue
		var top: Array = fs.top_confusion()
		if fs.recent_error_rate() >= 0.4 or (not top.is_empty() and top[1] >= 2) or fs.relapses >= 2:
			out.append(fs)
	out.sort_custom(func(x: FactState, y: FactState) -> bool:
		return x.recent_error_rate() > y.recent_error_rate())
	return out


## Confusion la plus persistante sous forme de paire de faits (ex. 7×8 ↔ 6×9),
## ou [] s'il n'y en a pas d'assez marquée pour un duel contre le Confondeur.
func strongest_confusion_pair(min_count: int = 3) -> Array:
	var best: Array = []
	var best_count := 0
	for fs in states.values():
		var top: Array = fs.top_confusion()
		if top.is_empty() or top[1] < min_count or top[1] <= best_count:
			continue
		var other := _fact_with_product(top[0], fs.key)
		if other != "":
			best = [fs.key, other]
			best_count = top[1]
	return best


## Une confusion est active si le fait a encore été manqué récemment.
func _confusion_is_active(key: String) -> bool:
	var fs: FactState = states[key]
	return fs.recent_error_rate() >= 0.2


## Au plus un duel par session : le Confondeur reste rare (6).
func _duel_done_this_session() -> bool:
	for i in range(journal.size() - 1, -1, -1):
		var e: Dictionary = journal[i]
		if e.get("type", "") == "session_start":
			return false
		if e.get("context", "") == MISSION_DUEL:
			return true
	return false


func _fact_with_product(product: int, exclude_key: String) -> String:
	var best := ""
	for fs in states.values():
		if fs.key != exclude_key and fs.fact.product() == product and not fs.fact.is_trivial():
			if best == "" or fs.key < best:
				best = fs.key
	return best


## Suggestion de mission pour le hub (8) : le moteur suggère sans imposer.
func suggest_mission() -> Dictionary:
	var pair := strongest_confusion_pair()
	var due := due_reviews()
	var counts := counts_by_state()
	if not pair.is_empty() and _confusion_is_active(pair[0]) and not _duel_done_this_session():
		return {"type": MISSION_DUEL, "pair": pair, "reason": "confusion"}
	# Les planètes attaquées d'abord : une révision due ne doit jamais attendre.
	if due.size() >= 3 or (not due.is_empty() and allowed_new_facts_count(due.size()) == 0):
		return {"type": MISSION_DEFENSE, "due": due.size(), "reason": "pirates"}
	if allowed_new_facts_count(due.size()) > 0:
		return {"type": MISSION_EXPLORATION, "reason": "new_facts"}
	if not due.is_empty():
		return {"type": MISSION_DEFENSE, "due": due.size(), "reason": "pirates"}
	if counts["mastered"] >= 5:
		return {"type": MISSION_ARENA, "reason": "fun"}
	return {"type": MISSION_EXPLORATION, "reason": "default"}


# ---------------------------------------------------------------------------
# Persistance et rejeu du journal (4.9)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var st := {}
	for key in states:
		st[key] = states[key].to_dict()
	return {
		"version": SAVE_VERSION,
		"session_id": session_id,
		"current_day": current_day,
		"calibration": calibration.duplicate(true),
		"states": st,
		"journal": journal.duplicate(true),
	}


static func from_dict(d: Dictionary, cfg: EngineConfig = null, seed: int = -1) -> LearningEngine:
	var engine := LearningEngine.new(cfg, seed)
	engine.session_id = int(d.get("session_id", 0))
	engine.current_day = int(d.get("current_day", 0))
	var cal: Dictionary = d.get("calibration", {})
	for mode in engine.calibration:
		var samples: Array = []
		for v in cal.get(mode, []):
			samples.append(int(v))
		engine.calibration[mode] = samples
	var st: Dictionary = d.get("states", {})
	for key in st:
		if engine.states.has(key):
			engine.states[key] = FactState.from_dict(st[key])
	engine.journal = []
	for e in d.get("journal", []):
		engine.journal.append(_normalize_entry(e))
	return engine


## Reconstruit entièrement l'état à partir du journal brut (4.9).
static func rebuild_from_journal(entries: Array, cfg: EngineConfig = null, seed: int = -1) -> LearningEngine:
	var engine := LearningEngine.new(cfg, seed)
	engine.replay(entries)
	return engine


## Réinitialise les états et rejoue `entries` (par défaut le journal courant).
func replay(entries: Array = []) -> void:
	var source := entries if not entries.is_empty() else journal.duplicate(true)
	_build_facts()
	for mode in calibration:
		calibration[mode] = []
	session_id = 0
	current_day = 0
	journal = []
	for raw in source:
		var e := _normalize_entry(raw)
		journal.append(e)
		match e.get("type", ""):
			"session_start":
				session_id = int(e["session"])
				current_day = int(e["day"])
			"result":
				if states.has(e["fact"]):
					_ingest_entry(states[e["fact"]], e)


## Les nombres relus depuis le JSON arrivent en float : on les remet en int.
static func _normalize_entry(raw: Dictionary) -> Dictionary:
	var e := raw.duplicate(true)
	for k in ["t", "session", "day", "given", "time_ms", "target_time_ms"]:
		if e.has(k):
			e[k] = int(e[k])
	if e.has("options"):
		var opts: Array = []
		for v in e["options"]:
			opts.append(int(v))
		e["options"] = opts
	return e


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _belongs_to_any(f: Fact, tables: Array) -> bool:
	for t in tables:
		if f.belongs_to(int(t)):
			return true
	return false


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Entrelacement (4.7) : jamais deux fois le même fait d'affilée.
func _without_adjacent_duplicates(queue: Array) -> Array:
	var out: Array = queue.duplicate()
	for i in range(1, out.size()):
		if out[i] == out[i - 1]:
			for j in range(i + 1, out.size()):
				if out[j] != out[i - 1] and (j + 1 >= out.size() or out[j + 1] != out[j]):
					var tmp = out[i]
					out[i] = out[j]
					out[j] = tmp
					break
	return out
