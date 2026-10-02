extends TestCase
## Validation du moteur par simulation d'élèves fictifs (4.10, feuille de route 10.2 étape 1).
## Une session = 2 missions de 20 calculs, une session par jour (sauf absences).

const MISSIONS_PER_SESSION := 2
const ITEMS_PER_MISSION := 20

var print_curves := true


## Joue `sessions` sessions ; `days` donne le jour de chaque session (sinon un jour par session).
## Retourne l'historique [{session, day, mastered, learning, consolidation, new, errors}].
func simulate(engine: LearningEngine, student: SimulatedStudent, sessions: int, days: Array = []) -> Array:
	var history: Array = []
	var last_key := ""
	for s in range(sessions):
		var day: int = days[s] if s < days.size() else s
		var summary := engine.start_session(day)
		last_key = ""  # l'entrelacement s'entend à l'intérieur d'une session
		assert_le(summary["planned_reviews"].size(), engine.config.max_reviews_per_session)
		assert_le(summary["planned_new"].size(), engine.config.max_new_facts_per_session)
		for _m in range(MISSIONS_PER_SESSION):
			var mission := engine.suggest_mission()
			var context := {"type": mission["type"]}
			if mission.has("pair"):
				context["pair"] = mission["pair"]
			for _i in range(ITEMS_PER_MISSION):
				var item := engine.next_item(context)
				_check_item(engine, item, last_key)
				last_key = item["fact"]
				var resp := student.answer(item, day)
				engine.report_result(item, resp["given"], resp["time_ms"])
		var stats := engine.end_session()
		var counts := engine.counts_by_state()
		counts["session"] = s + 1
		counts["day"] = day
		counts["errors"] = stats["errors"]
		counts["items"] = stats["items"]
		history.append(counts)
	return history


func _check_item(engine: LearningEngine, item: Dictionary, last_key: String) -> void:
	assert_ne(item["fact"], last_key, "même fait deux fois d'affilée")
	assert_true(item["mode"] in [LearningEngine.MODE_PRESENTATION, LearningEngine.MODE_QCM,
		LearningEngine.MODE_WHEEL, LearningEngine.MODE_DECOMPOSITION])
	if item["mode"] == LearningEngine.MODE_QCM:
		var options: Array = item["options"]
		assert_eq(options.size(), 4)
		assert_true(options.has(item["answer"]))
		for i in range(options.size()):
			for j in range(i + 1, options.size()):
				assert_ne(options[i], options[j], "distracteurs en double pour " + item["fact"])
			assert_true(options[i] > 0)
	if item["mode"] != LearningEngine.MODE_PRESENTATION:
		assert_true(item["target_time_ms"] > 0)
	match item["state"]:
		"new":
			assert_true(item["mode"] == LearningEngine.MODE_PRESENTATION or item["is_trivial"])
		"learning":
			assert_eq(item["mode"], LearningEngine.MODE_QCM)


func _first_session_reaching(history: Array, mastered: int) -> int:
	for h in history:
		if h["mastered"] >= mastered:
			return h["session"]
	return -1


func _print_curve(label: String, history: Array) -> void:
	if not print_curves:
		return
	var line := "  " + label + " : maîtrisés par session ->"
	for h in history:
		if (h["session"] - 1) % 5 == 0 or h["session"] == history.size():
			line += " s%d=%d" % [h["session"], h["mastered"]]
	print(line)


func test_average_student_masters_all_facts() -> void:
	var engine := LearningEngine.new(null, 100)
	var student := SimulatedStudent.new(100, 1.0)
	var history := simulate(engine, student, 70)
	_print_curve("élève moyen", history)
	var total := engine.states.size()
	var s_all := _first_session_reaching(history, total)
	assert_true(s_all > 0, "tout doit avoir été maîtrisé au moins une fois en 70 sessions")
	var s90 := _first_session_reaching(history, int(ceil(total * 0.9)))
	assert_true(s90 > 0 and s90 <= 35, "90 %% maîtrisés attendus avant la session 35, obtenu %d" % s90)
	# Régime stable : les fautes d'inattention (3 %) renvoient un fait en boîte 1,
	# mais la galaxie reste colonisée à plus de 90 %.
	assert_ge(history[-1]["mastered"], int(ceil(total * 0.9)))
	# Rejeu du journal : l'état doit se reconstruire à l'identique.
	var rebuilt := LearningEngine.rebuild_from_journal(engine.journal)
	for key in engine.states:
		assert_eq(rebuilt.states[key].to_dict(), engine.states[key].to_dict(), key)
	# Ce que le moteur déclare maîtrisé est réellement retenu par l'élève à 2 semaines.
	assert_ge(student.retention(engine, history[-1]["day"], 14.0), 0.9)


func test_slow_student_with_confusions_still_gets_there() -> void:
	var engine := LearningEngine.new(null, 200)
	var student := SimulatedStudent.new(200, 0.6, {"7x8": 54, "6x9": 56, "6x7": 48, "4x8": 36},
		{"qcm": 1600, "wheel": 3200})
	var history := simulate(engine, student, 110)
	_print_curve("élève lent", history)
	var total := engine.states.size()
	var s90 := _first_session_reaching(history, int(ceil(total * 0.9)))
	assert_true(s90 > 0 and s90 <= 60, "90 %% maîtrisés attendus avant la session 60, obtenu %d" % s90)
	assert_ge(history[-1]["mastered"], int(ceil(total * 0.85)))
	# Les confusions ont été enregistrées et le duel proposé au moins une fois.
	var fs: FactState = engine.states["7x8"]
	assert_true(fs.confusions.has("54"), "confusion 54 attendue pour 7x8")
	var duel_seen := false
	for e in engine.journal:
		if e.get("context", "") == LearningEngine.MISSION_DUEL:
			duel_seen = true
			break
	assert_true(duel_seen, "le Confondeur devrait avoir été proposé")
	# Le temps moteur a été calibré sur les faits triviaux (élève plus lent à la manette).
	assert_ge(engine.motor_base_ms("qcm"), 1400)


func test_fast_student_is_not_slowed_down() -> void:
	var engine := LearningEngine.new(null, 300)
	var student := SimulatedStudent.new(300, 1.4)
	var history := simulate(engine, student, 45)
	_print_curve("élève rapide", history)
	var total := engine.states.size()
	var s90 := _first_session_reaching(history, int(ceil(total * 0.9)))
	assert_true(s90 > 0 and s90 <= 25, "90 %% maîtrisés attendus avant la session 25, obtenu %d" % s90)
	assert_ge(history[-1]["mastered"], int(ceil(total * 0.9)))


func test_two_week_absence_causes_no_avalanche() -> void:
	var engine := LearningEngine.new(null, 400)
	var student := SimulatedStudent.new(400, 1.0)
	var days: Array = []
	for s in range(40):
		days.append(s if s < 20 else s + 14)
	var history := simulate(engine, student, 40, days)
	_print_curve("absence 2 semaines", history)
	# La session de retour (21e) a été plafonnée et n'a pas introduit d'avalanche :
	# au plus 10 révisions planifiées, et pas plus de 40 % d'erreurs.
	var back: Dictionary = history[20]
	assert_le(back["errors"], int(back["items"] * 0.4))
	# Les faits maîtrisés restent majoritairement maîtrisés après le retour.
	assert_ge(history[-1]["mastered"], history[19]["mastered"])


func test_mastered_facts_hold_over_long_term_play() -> void:
	var engine := LearningEngine.new(null, 500)
	var student := SimulatedStudent.new(500, 1.0)
	var history := simulate(engine, student, 120)
	var total := engine.states.size()
	var worst := total
	var sum := 0
	for h in history.slice(80):
		worst = mini(worst, h["mastered"])
		sum += h["mastered"]
	assert_ge(worst, int(total * 0.85), "pas d'effondrement de la maîtrise sur le long terme")
	assert_ge(float(sum) / 40.0, total * 0.9, "en moyenne, plus de 90 %% de la galaxie reste colonisée")
	# Le journal reste exploitable : chaque réponse est horodatée et contextualisée (4.9).
	var e: Dictionary = engine.journal[-1]
	for field in ["t", "session", "fact", "orientation", "mode", "options", "given", "correct", "time_ms", "context"]:
		assert_true(e.has(field), "champ manquant dans le journal : " + field)
