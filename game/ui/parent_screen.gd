extends Control
## Écran parent (10.1) : grille 10×10 des faits, faits à problème, temps de jeu,
## temps de réponse. Sert aussi d'outil de vérification de l'algorithme.


func _ready() -> void:
	UI.fill_background(self)
	var engine: LearningEngine = Game.engine
	var profile: Profile = Game.profile
	var v := UI.vbox(self, Vector2(24, 12), 2)
	v.add_child(UI.label("ÉCRAN PARENT  ·  %s" % profile.name, 18, UI.ACCENT))
	var counts := engine.counts_by_state()
	v.add_child(UI.label("Maîtrisés %d · En cours %d · Non vus %d    Sessions : %d    Temps de jeu : %s" % [
		counts["mastered"], counts["learning"] + counts["consolidation"], counts["new"],
		engine.session_id, UI.format_duration(profile.play_time_sec)], 11, UI.MUTED))

	_build_grid(engine, Vector2(24, 56))

	var right := UI.vbox(self, Vector2(300, 56), 2)
	right.add_child(UI.label("Faits qui posent problème", 13, UI.TEXT))
	var problems := engine.problem_facts()
	if problems.is_empty():
		right.add_child(UI.label("Aucun pour l'instant.", 11, UI.MUTED))
	for fs in problems.slice(0, 8):
		var top: Array = fs.top_confusion()
		var text := "%s = %d" % [UI.fact_text(fs.key), fs.fact.product()]
		if not top.is_empty():
			text += "   répond souvent %d (×%d)" % [top[0], top[1]]
		if fs.relapses > 0:
			text += "   rechutes : %d" % fs.relapses
		right.add_child(UI.label(text, 11, UI.BAD))
	right.add_child(UI.label(" ", 6))
	right.add_child(UI.label("Temps de réponse (temps moteur médian sur les faits triviaux)", 13, UI.TEXT))
	right.add_child(UI.label("QCM : %d ms   ·   Roue : %d ms   ·   seuil « rapide » = + %d ms" % [
		engine.motor_base_ms("qcm"), engine.motor_base_ms("wheel"), engine.config.speed_margin_ms], 11, UI.MUTED))
	right.add_child(UI.label(" ", 6))
	right.add_child(UI.label("Évolution du temps de réponse (médiane par session, hors présentations)", 13, UI.TEXT))
	right.add_child(UI.label(_response_time_trend(engine), 11, UI.MUTED))
	right.add_child(UI.label(" ", 6))
	right.add_child(UI.label("Révisions dues aujourd'hui : %d   ·   Journal : %d réponses" % [
		engine.due_reviews().size(), _journal_results(engine)], 11, UI.MUTED))

	var help := UI.label("B / Échap : retour au hub", 11, UI.MUTED)
	help.position = Vector2(24, 338)
	add_child(help)


func _build_grid(engine: LearningEngine, origin: Vector2) -> void:
	var cell := 22
	var lo: int = engine.config.table_min
	var hi: int = engine.config.table_max
	for b in range(lo, hi + 1):
		var head := UI.label(str(b), 10, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		head.position = origin + Vector2((b - lo + 1) * cell, 0)
		head.custom_minimum_size = Vector2(cell, cell)
		add_child(head)
	for a in range(lo, hi + 1):
		var head := UI.label(str(a), 10, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		head.position = origin + Vector2(0, (a - lo + 1) * cell)
		head.custom_minimum_size = Vector2(cell, cell)
		add_child(head)
		for b in range(lo, hi + 1):
			var fs: FactState = engine.fact_state(Fact.key_of(a, b))
			if fs == null:
				continue
			var r := UI.rect(UI.PLANET_COLORS[engine.planet_status(fs)], Vector2(cell - 2, cell - 2))
			r.position = origin + Vector2((b - lo + 1) * cell, (a - lo + 1) * cell)
			add_child(r)
			var l := UI.label(str(fs.box) if fs.state != FactState.State.NEW else "", 9, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
			l.add_theme_constant_override("outline_size", 0)
			l.position = Vector2(0, 2)
			l.custom_minimum_size = Vector2(cell - 2, 0)
			r.add_child(l)
	var legend := UI.hbox(self, 8)
	legend.position = origin + Vector2(0, (hi - lo + 2) * cell + 4)
	for entry in [["non vu", "dark"], ["en cours (n° de boîte)", "orbit"], ["maîtrisé", "colonized"], ["à réviser", "besieged"]]:
		var h := UI.hbox(legend, 3)
		h.add_child(UI.rect(UI.PLANET_COLORS[entry[1]], Vector2(10, 10)))
		h.add_child(UI.label(entry[0], 10, UI.MUTED))


func _journal_results(engine: LearningEngine) -> int:
	var n := 0
	for e in engine.journal:
		if e.get("type", "") == "result":
			n += 1
	return n


## Médiane des temps de réponse corrects par session, sur les 8 dernières sessions.
func _response_time_trend(engine: LearningEngine) -> String:
	var per_session := {}
	for e in engine.journal:
		if e.get("type", "") != "result" or e.get("mode", "") == LearningEngine.MODE_PRESENTATION or not e.get("correct", false):
			continue
		var s: int = int(e["session"])
		if not per_session.has(s):
			per_session[s] = []
		per_session[s].append(int(e["time_ms"]))
	var sessions := per_session.keys()
	sessions.sort()
	var parts: Array = []
	for s in sessions.slice(maxi(0, sessions.size() - 8)):
		parts.append("s%d : %d ms" % [s, FactState.median(per_session[s])])
	return "  ·  ".join(parts) if not parts.is_empty() else "Pas encore de données."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("canon_B") or event.is_action_pressed("pause") or event.is_action_pressed("ecran_parent"):
		get_tree().change_scene_to_file("res://game/hub.tscn")
