extends TestCase
## Règles du moteur d'apprentissage (section 4).

var engine: LearningEngine


func setup() -> void:
	engine = LearningEngine.new(null, 1234)


## Demande un item pour un fait précis et y répond.
func _answer(key: String, correct: bool, time_ms: int = 1500, context: Dictionary = {}) -> Dictionary:
	var ctx := context.duplicate()
	ctx["fact"] = key
	var item := engine.next_item(ctx)
	var given: int = item["accepted"][0] if correct else _wrong_answer(item)
	var outcome := engine.report_result(item, given, time_ms)
	outcome["item"] = item
	return outcome


func _wrong_answer(item: Dictionary) -> int:
	if item["mode"] == LearningEngine.MODE_QCM:
		for o in item["options"]:
			if not item["accepted"].has(o):
				return o
	return int(item["answer"]) + 2


func _fs(key: String) -> FactState:
	return engine.states[key]


# --- Composition de session (4.7) --------------------------------------------

func test_first_session_introduces_2_or_3_new_facts_in_table_order() -> void:
	var summary := engine.start_session(0)
	assert_ge(summary["planned_new"].size(), 2)
	assert_le(summary["planned_new"].size(), 3)
	# Ordre de découverte (5.2) : les faits de la table de 2 d'abord.
	for key in summary["planned_new"]:
		assert_true(Fact.from_key(key).belongs_to(2), "attendu table de 2, obtenu " + key)
	assert_eq(summary["due"], 0)


func test_new_fact_is_presented_then_asked_in_qcm_2_or_3_items_later() -> void:
	engine.start_session(0)
	var presentation_key := ""
	var items: Array = []
	for _i in range(12):
		var item := engine.next_item()
		items.append(item)
		if item["mode"] == LearningEngine.MODE_PRESENTATION and presentation_key == "":
			presentation_key = item["fact"]
		engine.report_result(item, item["accepted"][0], 1500)
	assert_ne(presentation_key, "", "aucune présentation dans la première session")
	var first := -1
	var second := -1
	for i in range(items.size()):
		if items[i]["fact"] == presentation_key:
			if first == -1:
				first = i
			elif second == -1:
				second = i
	assert_ne(second, -1, "le fait présenté n'est pas revenu")
	assert_ge(second - first, 2)
	assert_le(second - first, 3)
	assert_eq(items[second]["mode"], LearningEngine.MODE_QCM)
	assert_eq(items[second]["options"].size(), 4)
	assert_true(items[second]["options"].has(items[second]["answer"]))


func test_trivial_facts_skip_presentation() -> void:
	engine.start_session(0)
	var item := engine.next_item({"fact": "1x7"})
	assert_eq(item["mode"], LearningEngine.MODE_QCM)


func test_never_same_fact_twice_in_a_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for s in range(6):
		engine.start_session(s)
		var last := ""
		for _i in range(40):
			var item := engine.next_item()
			assert_ne(item["fact"], last, "session %d" % s)
			last = item["fact"]
			var correct := rng.randf() < 0.7
			engine.report_result(item, item["accepted"][0] if correct else _wrong_answer(item), 2000)
		engine.end_session()


func test_wrong_answer_comes_back_2_or_3_items_later() -> void:
	engine.start_session(0)
	var item := engine.next_item()
	while item["mode"] == LearningEngine.MODE_PRESENTATION:
		engine.report_result(item, item["answer"], 0)
		item = engine.next_item()
	engine.report_result(item, _wrong_answer(item), 2000)
	var key: String = item["fact"]
	var position := -1
	for i in range(1, 5):
		var next := engine.next_item()
		engine.report_result(next, next["accepted"][0], 1500)
		if next["fact"] == key and position == -1:
			position = i
	assert_ge(position, 2)
	assert_le(position, 3)


func test_anti_frustration_inserts_easy_mastered_fact_after_2_errors() -> void:
	_fs("2x5").state = FactState.State.MASTERED
	_fs("2x5").box = 5
	_fs("3x4").state = FactState.State.LEARNING
	_fs("4x6").state = FactState.State.LEARNING
	engine.start_session(0)
	_answer("3x4", false)
	_answer("4x6", false)
	var item := engine.next_item()
	assert_eq(item["fact"], "2x5")


func test_no_new_facts_when_recent_error_rate_is_high() -> void:
	engine.start_session(0)
	for key in ["2x3", "2x4", "3x4", "4x5", "6x7"]:
		_fs(key).state = FactState.State.LEARNING
		_answer(key, false)
	assert_eq(engine.allowed_new_facts_count(0), 0)
	assert_eq(engine.recent_error_rate(), 1.0)


func test_no_new_facts_when_many_reviews_pending() -> void:
	assert_eq(engine.allowed_new_facts_count(engine.config.new_facts_pending_reviews_limit + 1), 0)
	assert_ge(engine.allowed_new_facts_count(engine.config.new_facts_pending_reviews_limit), 2)


func test_practice_answer_does_not_postpone_the_planned_review() -> void:
	var fs := _fs("4x8")
	fs.state = FactState.State.CONSOLIDATION
	fs.box = 3
	engine.session_id = 1
	engine._schedule(fs, 1, 0)  # dû à la session 3, jour 3
	engine.start_session(1)  # session 2, pas encore dû
	var out := _answer("4x8", true, 2000)
	assert_false(out["item"]["is_due"])
	assert_eq(fs.box, 3, "pas de progression hors révision due")
	assert_eq(fs.due_session, 3)
	assert_eq(fs.due_day, 3)
	# Une erreur, elle, reprogramme immédiatement (boîte 1).
	_answer("4x8", false, 2000)
	assert_eq(fs.box, 1)
	assert_eq(fs.due_session, 2)


func test_reviews_capped_and_most_overdue_first_after_long_absence() -> void:
	# 30 faits en consolidation, dus depuis longtemps avec des retards différents.
	var i := 0
	for key in engine.states:
		if i >= 30:
			break
		var fs: FactState = engine.states[key]
		fs.state = FactState.State.CONSOLIDATION
		fs.box = 3
		fs.due_session = 1
		fs.due_day = i  # retard croissant pour les premiers
		fs.interval_days = 3
		fs.interval_sessions = 2
		i += 1
	var summary := engine.start_session(40)
	assert_eq(summary["due"], 30)
	assert_eq(summary["planned_reviews"].size(), engine.config.max_reviews_per_session)
	var due := engine.due_reviews()
	for j in range(1, due.size()):
		assert_true(engine.lateness(due[j - 1]) >= engine.lateness(due[j]), "tri par retard relatif")
	assert_eq(summary["planned_new"].size(), 0, "pas de faits nouveaux quand les révisions s'accumulent")


# --- Règles de passage (4.5) ----------------------------------------------------

func test_presentation_moves_new_to_learning_box_1() -> void:
	engine.start_session(0)
	var out := _answer("3x4", true)
	assert_eq(out["item"]["mode"], LearningEngine.MODE_PRESENTATION)
	assert_eq(_fs("3x4").state, FactState.State.LEARNING)
	assert_eq(_fs("3x4").box, 1)


func test_fast_correct_adds_a_box_slow_correct_keeps_it() -> void:
	engine.start_session(0)
	_answer("3x4", true)  # présentation, boîte 1
	var out := _answer("3x4", true, engine.target_time_ms("qcm") + 500)  # juste mais lent
	assert_false(out["fast"])
	assert_eq(_fs("3x4").box, 1)
	out = _answer("3x4", true, 1000)  # juste et rapide, fait dû (boîte 1 = même session)
	assert_true(out["fast"])
	assert_eq(_fs("3x4").box, 2)


func test_wrong_answer_returns_to_box_1_and_records_confusion() -> void:
	engine.start_session(0)
	_fs("7x8").state = FactState.State.CONSOLIDATION
	_fs("7x8").box = 3
	var item := engine.next_item({"fact": "7x8"})
	assert_eq(item["mode"], LearningEngine.MODE_WHEEL)
	engine.report_result(item, 54, 3000)
	assert_eq(_fs("7x8").box, 1)
	assert_eq(_fs("7x8").confusions, {"54": 1})
	assert_eq(_fs("7x8").state, FactState.State.CONSOLIDATION)
	assert_eq(_fs("7x8").relapses, 0)


func test_anti_random_fast_qcm_answer_does_not_progress() -> void:
	engine.start_session(0)
	_answer("3x4", true)
	var out := _answer("3x4", true, 250)
	assert_true(out["suspicious"])
	assert_eq(_fs("3x4").box, 1)
	assert_eq(_fs("3x4").qcm_streak, 0)
	assert_eq(engine.journal[-1]["suspicious"], true)
	# Le mitraillage signalé par le jeu est traité de la même façon.
	var item := engine.next_item({"fact": "3x4"})
	out = engine.report_result(item, item["answer"], 2000, {"mashing": true})
	assert_true(out["suspicious"])
	assert_eq(_fs("3x4").box, 1)


func test_learning_to_consolidation_needs_3_qcm_successes_over_2_sessions() -> void:
	engine.start_session(0)
	_answer("3x4", true)  # présentation
	_answer("3x4", true, 1000)
	_answer("3x4", true, 1000)
	_answer("3x4", true, 1000)
	assert_eq(_fs("3x4").qcm_streak, 3)
	assert_eq(_fs("3x4").state, FactState.State.LEARNING, "3 réussites dans une seule session ne suffisent pas")
	engine.start_session(1)
	var out := _answer("3x4", true, 1000)
	assert_eq(out["item"]["mode"], LearningEngine.MODE_QCM)
	assert_eq(_fs("3x4").state, FactState.State.CONSOLIDATION)


func test_full_lifecycle_to_mastery_and_relapse() -> void:
	# Session 1, jour 0 : présentation puis QCM rapide -> boîte 2.
	engine.start_session(0)
	assert_eq(_answer("6x7", true)["item"]["mode"], LearningEngine.MODE_PRESENTATION)
	assert_eq(_answer("6x7", true, 1000)["item"]["mode"], LearningEngine.MODE_QCM)
	assert_eq(_fs("6x7").box, 2)
	# Session 2, jour 1 : dû (1 session, 1 jour) -> boîte 3, consolidation (3 réussites / 2 sessions).
	engine.start_session(1)
	_answer("6x7", true, 1000)
	assert_eq(_fs("6x7").state, FactState.State.LEARNING)
	assert_eq(_fs("6x7").box, 3)
	engine.start_session(2)
	assert_false(engine.is_due(_fs("6x7")), "boîte 3 : 2 sessions et 3 jours minimum")
	# Session 4, jour 4 : dû -> consolidation, boîte 4, à la roue.
	engine.start_session(4)
	var out := _answer("6x7", true, 1000)
	assert_eq(out["item"]["mode"], LearningEngine.MODE_QCM)
	assert_eq(_fs("6x7").state, FactState.State.CONSOLIDATION)
	assert_eq(_fs("6x7").box, 4)
	# Session 7, jour 11 : roue rapide alors que la boîte 4 est atteinte -> maîtrisé, boîte 5.
	engine.session_id = 6
	engine.start_session(11)
	out = _answer("6x7", true, 2000)
	assert_eq(out["item"]["mode"], LearningEngine.MODE_WHEEL)
	assert_true(out["fast"])
	assert_true(out["mastered_now"])
	assert_eq(_fs("6x7").box, 5)
	assert_eq(_fs("6x7").state, FactState.State.MASTERED)
	assert_eq(_fs("6x7").due_day, 32, "boîte 5 : 21 jours")
	assert_eq(_fs("6x7").due_session, 11, "boîte 5 : 4 sessions")
	# Une réponse lente à la roue sur un fait en consolidation ne suffit pas à le maîtriser.
	_fs("6x7").state = FactState.State.CONSOLIDATION
	_fs("6x7").box = 4
	engine.session_id = 10
	engine.start_session(32)
	out = _answer("6x7", true, 9000)
	assert_false(out["fast"])
	assert_eq(_fs("6x7").state, FactState.State.CONSOLIDATION)
	_fs("6x7").state = FactState.State.MASTERED
	# Erreur sur un fait maîtrisé : rechute comptée, retour en consolidation, boîte 1.
	engine.session_id = 20
	engine.start_session(60)
	out = _answer("6x7", false, 3000)
	assert_true(out["relapse"])
	assert_eq(_fs("6x7").relapses, 1)
	assert_eq(_fs("6x7").state, FactState.State.CONSOLIDATION)
	assert_eq(_fs("6x7").box, 1)
	# Intervalles plus prudents après rechute : boîte 3 -> 2 jours au lieu de 3.
	_fs("6x7").box = 3
	engine._schedule(_fs("6x7"), engine.session_id, engine.current_day)
	assert_eq(_fs("6x7").interval_days, 2)


# --- Intervalles (4.6) ---------------------------------------------------------

func test_review_intervals_table() -> void:
	var expected := {1: [0, 0], 2: [1, 1], 3: [2, 3], 4: [3, 7], 5: [4, 21]}
	for box in expected:
		var fs := FactState.new(Fact.make(3, 4))
		fs.state = FactState.State.CONSOLIDATION
		fs.box = box
		engine._schedule(fs, 10, 100)
		assert_eq(fs.due_session, 10 + expected[box][0], "boîte %d sessions" % box)
		assert_eq(fs.due_day, 100 + expected[box][1], "boîte %d jours" % box)


func test_review_due_only_when_both_minimums_reached() -> void:
	var fs := _fs("3x4")
	fs.state = FactState.State.CONSOLIDATION
	fs.box = 3
	engine.session_id = 1
	engine.current_day = 0
	engine._schedule(fs, 1, 0)  # dû à la session 3 et au jour 3
	engine.session_id = 3
	engine.current_day = 1
	assert_false(engine.is_due(fs), "sessions atteintes mais pas les jours")
	engine.session_id = 2
	engine.current_day = 5
	assert_false(engine.is_due(fs), "jours atteints mais pas les sessions")
	engine.session_id = 3
	engine.current_day = 3
	assert_true(engine.is_due(fs))


# --- Seuil de rapidité (4.4) ---------------------------------------------------

func test_motor_base_calibrated_on_trivial_facts() -> void:
	assert_eq(engine.motor_base_ms("qcm"), engine.config.default_motor_base_ms["qcm"])
	engine.start_session(0)
	for key in ["1x3", "1x5", "1x8"]:
		_answer(key, true, 900)
	assert_eq(engine.motor_base_ms("qcm"), 900)
	assert_eq(engine.target_time_ms("qcm"), 900 + engine.config.speed_margin_ms)
	assert_eq(engine.motor_base_ms("wheel"), engine.config.default_motor_base_ms["wheel"])


# --- Orientation (4.1) ---------------------------------------------------------

func test_weak_orientation_presented_more_often() -> void:
	var fs := _fs("3x7")
	fs.orientation_stats["3x7"] = {"attempts": 5, "correct": 5, "times": [1000, 1000, 1000]}
	fs.orientation_stats["7x3"] = {"attempts": 5, "correct": 2, "times": [2500, 2600]}
	fs.state = FactState.State.LEARNING
	engine.start_session(0)
	var weak := 0
	for _i in range(200):
		var item := engine.next_item({"fact": "3x7"})
		if item["orientation"] == "7x3":
			weak += 1
	assert_ge(weak, 120, "orientation faible présentée dans moins de 60 % des cas")


# --- Modes et contextes (4.3, 4.10, 6) ------------------------------------------

func test_mode_follows_state() -> void:
	engine.start_session(0)
	assert_eq(engine.next_item({"fact": "4x6"})["mode"], LearningEngine.MODE_PRESENTATION)
	_fs("4x6").state = FactState.State.LEARNING
	assert_eq(engine.next_item({"fact": "4x6"})["mode"], LearningEngine.MODE_QCM)
	_fs("4x6").state = FactState.State.CONSOLIDATION
	assert_eq(engine.next_item({"fact": "4x6"})["mode"], LearningEngine.MODE_WHEEL)
	_fs("4x6").state = FactState.State.MASTERED
	assert_eq(engine.next_item({"fact": "4x6"})["mode"], LearningEngine.MODE_WHEEL)
	var item := engine.next_item({"fact": "4x6", "mode_hint": "decomposition"})
	assert_eq(item["mode"], LearningEngine.MODE_DECOMPOSITION)
	assert_eq(item["question"], "24")
	assert_eq(item["accepted"], [4, 6])
	# La décomposition est réservée aux faits maîtrisés.
	_fs("4x6").state = FactState.State.CONSOLIDATION
	assert_eq(engine.next_item({"fact": "4x6", "mode_hint": "decomposition"})["mode"], LearningEngine.MODE_WHEEL)


func test_arena_and_boss_serve_only_mastered_facts() -> void:
	for key in ["2x3", "2x7", "3x7", "7x9"]:
		_fs(key).state = FactState.State.MASTERED
		_fs(key).box = 5
	engine.start_session(0)
	for _i in range(20):
		var item := engine.next_item({"type": "arena"})
		assert_eq(item["state"], "mastered")
		engine.report_result(item, item["answer"], 2000)
	for _i in range(10):
		var item := engine.next_item({"type": "boss", "tables": [7]})
		assert_eq(item["state"], "mastered")
		assert_true(Fact.from_key(item["fact"]).belongs_to(7))
		engine.report_result(item, item["answer"], 2000)


func test_duel_alternates_between_the_two_confused_facts() -> void:
	_fs("7x8").state = FactState.State.CONSOLIDATION
	_fs("6x9").state = FactState.State.CONSOLIDATION
	engine.start_session(0)
	var seen: Array = []
	for _i in range(6):
		var item := engine.next_item({"type": "duel", "pair": ["7x8", "6x9"]})
		seen.append(item["fact"])
		engine.report_result(item, item["answer"], 2000)
	assert_eq(seen, ["7x8", "6x9", "7x8", "6x9", "7x8", "6x9"])


func test_defense_serves_due_reviews_first() -> void:
	_fs("3x9").state = FactState.State.CONSOLIDATION
	_fs("3x9").box = 2
	_fs("3x9").due_session = 1
	_fs("3x9").due_day = 1
	engine.start_session(5)
	var item := engine.next_item({"type": "defense"})
	assert_eq(item["fact"], "3x9")
	assert_true(item["is_due"])


# --- Lecture de l'état (5, 10.1) -----------------------------------------------

func test_galaxy_map_and_boss_ready() -> void:
	var map := engine.galaxy_map()
	assert_eq(map[2]["total"], 10)
	assert_false(map[2]["complete"])
	for key in map[2]["facts"]:
		assert_eq(map[2]["facts"][key]["status"], "dark")
	assert_false(engine.boss_ready(2))
	for key in map[2]["facts"]:
		_fs(key).state = FactState.State.MASTERED
		_fs(key).box = 5
	assert_true(engine.boss_ready(2))
	assert_true(engine.galaxy_map()[2]["complete"])
	assert_eq(engine.galaxy_map()[2]["facts"]["2x7"]["status"], "colonized")


func test_suggest_mission() -> void:
	assert_eq(engine.suggest_mission()["type"], LearningEngine.MISSION_EXPLORATION)
	for key in ["3x4", "3x5", "3x6"]:
		_fs(key).state = FactState.State.CONSOLIDATION
		_fs(key).box = 2
	engine.session_id = 5
	engine.current_day = 10
	assert_eq(engine.suggest_mission()["type"], LearningEngine.MISSION_DEFENSE)
	# Confusion persistante et encore active -> duel contre le Confondeur, une fois par session.
	engine.start_session(11)
	_fs("7x8").state = FactState.State.CONSOLIDATION
	_fs("7x8").confusions = {"54": 4}
	_fs("7x8").history = [{"correct": false, "time_ms": 3000, "mode": "wheel", "orientation": "7x8", "session": 11, "fast": false}]
	var s := engine.suggest_mission()
	assert_eq(s["type"], LearningEngine.MISSION_DUEL)
	assert_eq(s["pair"], ["7x8", "6x9"])
	var seen: Array = []
	for _i in range(8):
		var item := engine.next_item({"type": "duel", "pair": s["pair"]})
		seen.append(item["fact"])
		engine.report_result(item, item["answer"], 2000)
	assert_eq(seen.slice(0, 6), ["7x8", "6x9", "7x8", "6x9", "7x8", "6x9"])
	assert_false(seen[6] in ["7x8", "6x9"], "après 3 passages chacun, retour à la file normale")
	assert_ne(engine.suggest_mission()["type"], LearningEngine.MISSION_DUEL, "un seul duel par session")


func test_problem_facts_lists_confusions_and_errors() -> void:
	_fs("7x8").state = FactState.State.CONSOLIDATION
	_fs("7x8").confusions = {"54": 2}
	assert_eq(engine.problem_facts().size(), 1)
	assert_eq(engine.problem_facts()[0].key, "7x8")
