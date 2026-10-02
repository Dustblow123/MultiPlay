class_name FactState
extends RefCounted
## État d'un fait pour un enfant (4.2 et 4.3). Logique pure, sérialisable en JSON.

enum State { NEW, LEARNING, CONSOLIDATION, MASTERED }
const STATE_NAMES := ["new", "learning", "consolidation", "mastered"]

var fact: Fact
var state: int = State.NEW
var box: int = 0

## Prochaine révision : jour (nombre de jours depuis l'époque) et numéro de session.
var due_day: int = 0
var due_session: int = 0
## Intervalles utilisés pour calculer le retard relatif.
var interval_days: int = 0
var interval_sessions: int = 0

## 5 dernières tentatives : {correct, time_ms, mode, orientation, session, fast}.
var history: Array = []
## Nombre de régressions après maîtrise.
var relapses: int = 0
## Mauvaises réponses données : "54" -> 3.
var confusions: Dictionary = {}
## Statistiques par orientation : "3x7" -> {attempts, correct, times: [..]}.
var orientation_stats: Dictionary = {}

## Série de réussites consécutives en QCM et sessions où elles ont eu lieu.
var qcm_streak: int = 0
var qcm_streak_sessions: Array = []
## Réussites rapides consécutives à la roue (vers la maîtrise).
var wheel_fast_streak: int = 0

var last_session: int = -1
var last_day: int = -1
var total_attempts: int = 0
var total_correct: int = 0


func _init(f: Fact = null) -> void:
	fact = f


var key: String:
	get:
		return fact.key


func state_name() -> String:
	return STATE_NAMES[state]


func is_mastered() -> bool:
	return state == State.MASTERED


## Temps médian récent (plus robuste qu'une moyenne), en ms. 0 si inconnu.
func median_time_ms() -> int:
	var times: Array = []
	for h in history:
		if h.get("correct", false) and h.get("mode", "") != "presentation":
			times.append(int(h.get("time_ms", 0)))
	return FactState.median(times)


## Taux d'erreur sur l'historique récent (hors présentations).
func recent_error_rate() -> float:
	var n := 0
	var errors := 0
	for h in history:
		if h.get("mode", "") == "presentation":
			continue
		n += 1
		if not h.get("correct", false):
			errors += 1
	return 0.0 if n == 0 else float(errors) / float(n)


## Confusion la plus fréquente : [réponse, fréquence] ou [] si aucune.
func top_confusion() -> Array:
	var best := []
	for answer in confusions:
		var c: int = confusions[answer]
		if best.is_empty() or c > best[1]:
			best = [int(answer), c]
	return best


## Confusions triées par fréquence décroissante (liste de nombres).
func confusions_by_frequency() -> Array:
	var keys := confusions.keys()
	keys.sort_custom(func(x, y): return confusions[x] > confusions[y])
	var out := []
	for k in keys:
		out.append(int(k))
	return out


func record_history(entry: Dictionary, history_size: int) -> void:
	history.append(entry)
	while history.size() > history_size:
		history.pop_front()


func orientation_stat(orientation: String) -> Dictionary:
	if not orientation_stats.has(orientation):
		orientation_stats[orientation] = {"attempts": 0, "correct": 0, "times": []}
	return orientation_stats[orientation]


static func median(values: Array) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return int(sorted[n / 2])
	return int((sorted[n / 2 - 1] + sorted[n / 2]) / 2)


func to_dict() -> Dictionary:
	return {
		"key": key,
		"state": state,
		"box": box,
		"due_day": due_day,
		"due_session": due_session,
		"interval_days": interval_days,
		"interval_sessions": interval_sessions,
		"history": history.duplicate(true),
		"relapses": relapses,
		"confusions": confusions.duplicate(),
		"orientation_stats": orientation_stats.duplicate(true),
		"qcm_streak": qcm_streak,
		"qcm_streak_sessions": qcm_streak_sessions.duplicate(),
		"wheel_fast_streak": wheel_fast_streak,
		"last_session": last_session,
		"last_day": last_day,
		"total_attempts": total_attempts,
		"total_correct": total_correct,
	}


static func from_dict(d: Dictionary) -> FactState:
	var fs := FactState.new(Fact.from_key(d["key"]))
	fs.state = int(d.get("state", State.NEW))
	fs.box = int(d.get("box", 0))
	fs.due_day = int(d.get("due_day", 0))
	fs.due_session = int(d.get("due_session", 0))
	fs.interval_days = int(d.get("interval_days", 0))
	fs.interval_sessions = int(d.get("interval_sessions", 0))
	fs.history = []
	for h in d.get("history", []):
		fs.history.append({
			"correct": bool(h.get("correct", false)),
			"time_ms": int(h.get("time_ms", 0)),
			"mode": str(h.get("mode", "")),
			"orientation": str(h.get("orientation", "")),
			"session": int(h.get("session", 0)),
			"fast": bool(h.get("fast", false)),
		})
	fs.relapses = int(d.get("relapses", 0))
	# Les clés JSON sont toujours des chaînes ; les valeurs peuvent revenir en float.
	var conf: Dictionary = d.get("confusions", {})
	for k in conf:
		fs.confusions[str(k)] = int(conf[k])
	var os: Dictionary = d.get("orientation_stats", {})
	for k in os:
		var s: Dictionary = os[k]
		var times: Array = []
		for t in s.get("times", []):
			times.append(int(t))
		fs.orientation_stats[str(k)] = {
			"attempts": int(s.get("attempts", 0)),
			"correct": int(s.get("correct", 0)),
			"times": times,
		}
	fs.qcm_streak = int(d.get("qcm_streak", 0))
	fs.qcm_streak_sessions = []
	for s in d.get("qcm_streak_sessions", []):
		fs.qcm_streak_sessions.append(int(s))
	fs.wheel_fast_streak = int(d.get("wheel_fast_streak", 0))
	fs.last_session = int(d.get("last_session", -1))
	fs.last_day = int(d.get("last_day", -1))
	fs.total_attempts = int(d.get("total_attempts", 0))
	fs.total_correct = int(d.get("total_correct", 0))
	return fs
