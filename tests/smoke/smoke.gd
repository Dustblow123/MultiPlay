extends Node
## Test de fumée du prototype en mode headless : parcourt menu, hub, mission
## (QCM, roue, présentation), résultats et écran parent en pilotant les scènes
## par leurs méthodes publiques. Quitte avec le code 1 en cas d'erreur.
##
##   godot --headless --path . res://tests/smoke/smoke.tscn

var _errors: Array = []


func _check(cond: bool, message: String) -> void:
	if not cond:
		_errors.append(message)
		printerr("SMOKE ÉCHEC : " + message)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Profil de test isolé.
	var profile := Profile.create("Fumée")
	profile.id = "smoke_test_profile"
	Game.set_profile(profile)

	# Hub.
	var hub: Node = load("res://game/hub.tscn").instantiate()
	add_child(hub)
	await get_tree().process_frame
	_check(Game.engine.session_active, "le hub doit ouvrir une session du moteur")
	_check(hub._options.size() >= 4, "le hub doit proposer des missions")
	hub.queue_free()
	await get_tree().process_frame

	# Mission d'exploration : on joue 20 calculs en répondant juste (sauf un faux).
	Game.mission_context = {"type": LearningEngine.MISSION_EXPLORATION}
	var mission: Node = load("res://game/mission/mission.tscn").instantiate()
	add_child(mission)
	await get_tree().process_frame
	var played := 0
	var wrong_done := false
	var guard := 0
	while mission.phase != mission.Phase.DONE and guard < 400:
		guard += 1
		if mission.phase == mission.Phase.ACTIVE:
			var it: Dictionary = mission.item
			match it["mode"]:
				LearningEngine.MODE_PRESENTATION:
					mission._acknowledge_presentation()
				LearningEngine.MODE_QCM:
					var idx: int = it["options"].find(it["answer"])
					if not wrong_done:
						wrong_done = true
						mission.press_cannon((idx + 1) % 4)
						_check(mission.shield == Game.SHIELD_MAX - 1, "une erreur coûte un point de bouclier")
						_check(mission.phase == mission.Phase.ACTIVE, "une erreur ne termine pas le calcul")
					mission.press_cannon(idx)
				_:
					for ch in str(it["answer"]):
						mission.wheel_add_digit(int(ch))
					mission.wheel_fire()
			played += 1
			_check(mission.phase == mission.Phase.FEEDBACK or mission.phase == mission.Phase.DONE, "la réponse doit résoudre le calcul")
		# Laisse passer le retour visuel.
		for _i in range(3):
			mission._process(0.3)
			await get_tree().process_frame
		if not is_instance_valid(mission) or mission.get_parent() == null:
			break
	_check(played >= 15, "au moins 15 calculs joués, obtenu %d" % played)
	_check(Game.engine.journal.size() > played, "le journal doit contenir les réponses")
	_check(Game.last_mission_result.get("items", 0) >= 15, "résultat de mission renseigné")
	await get_tree().process_frame

	# L'écran de résultats et l'écran parent se construisent sans erreur.
	var results: Node = load("res://game/ui/results.tscn").instantiate()
	add_child(results)
	await get_tree().process_frame
	results.queue_free()
	var parent_screen: Node = load("res://game/ui/parent_screen.tscn").instantiate()
	add_child(parent_screen)
	await get_tree().process_frame
	parent_screen.queue_free()
	var options: Node = load("res://game/ui/options.tscn").instantiate()
	add_child(options)
	await get_tree().process_frame
	options._adjust(1)
	_check(is_equal_approx(float(Game.profile.settings["deadzone"]), 0.4), "la zone morte se règle par pas de 0,05")
	options.queue_free()
	await get_tree().process_frame

	# Navigation de menu : détection de front, pas de rafale, neutre obligatoire.
	var nav := MenuNav.new()
	Input.action_press("menu_bas", 1.0)
	_check(nav.poll_vertical(0.016) == 0, "stick déjà incliné à l'ouverture : ignoré tant qu'il n'est pas revenu au neutre")
	Input.action_release("menu_bas")
	nav.poll_vertical(0.016)
	Input.action_press("menu_bas", 1.0)
	_check(nav.poll_vertical(0.016) == 1, "premier front : un déplacement")
	var moves := 0
	for _i in range(20):
		moves += absi(nav.poll_vertical(0.016))
	_check(moves == 0, "maintenir 0,3 s ne répète pas encore, obtenu %d" % moves)
	for _i in range(60):
		moves += absi(nav.poll_vertical(0.016))
	_check(moves >= 3 and moves <= 5, "maintenir ~1 s répète à cadence lente, obtenu %d" % moves)
	Input.action_release("menu_bas")
	_check(Sfx._streams.size() >= 8, "les effets sonores sont générés")

	# Boutique du vaisseau : achat en poussière d'étoile, refus si elle manque.
	Game.profile.stardust = 25
	_check(Cosmetics.buy_or_equip(Game.profile, "color", "blue"), "achat possible avec assez de poussière")
	_check(Game.profile.stardust == 5, "le prix est débité")
	_check(not Cosmetics.buy_or_equip(Game.profile, "color", "gold"), "achat refusé sans poussière")
	_check(Cosmetics.buy_or_equip(Game.profile, "color", "blue"), "ré-équiper un cosmétique acquis est gratuit")
	var ship_screen: Node = load("res://game/ui/ship_screen.tscn").instantiate()
	add_child(ship_screen)
	await get_tree().process_frame
	ship_screen.queue_free()
	await get_tree().process_frame

	# Arène puis boss : faits de la table de 2 maîtrisés.
	for key in Game.engine.states:
		var fs: FactState = Game.engine.states[key]
		if fs.fact.belongs_to(2):
			fs.state = FactState.State.MASTERED
			fs.box = 5
	_check(Game.engine.boss_ready(2), "boss de la table de 2 prêt")
	for ctx in [{"type": LearningEngine.MISSION_ARENA}, {"type": LearningEngine.MISSION_BOSS, "tables": [2], "boss": true}]:
		Game.mission_context = ctx
		var m: Node = load("res://game/mission/mission.tscn").instantiate()
		add_child(m)
		await get_tree().process_frame
		var g := 0
		while m.phase != m.Phase.DONE and g < 300:
			g += 1
			if m.phase == m.Phase.ACTIVE:
				var it: Dictionary = m.item
				_check(it["state"] == "mastered", "%s : faits maîtrisés seulement" % ctx["type"])
				match it["mode"]:
					LearningEngine.MODE_QCM:
						m.press_cannon(it["options"].find(it["answer"]))
					LearningEngine.MODE_DECOMPOSITION:
						for ch in str(it["accepted"][0]):
							m.wheel_add_digit(int(ch))
						m.wheel_fire()
						_check(m.phase == m.Phase.ACTIVE, "après un facteur, il reste l'autre à achever")
						for ch in str(m._decomp_remaining):
							m.wheel_add_digit(int(ch))
						m.wheel_fire()
					_:
						for ch in str(it["answer"]):
							m.wheel_add_digit(int(ch))
						m.wheel_fire()
			for _i in range(3):
				m._process(0.3)
				await get_tree().process_frame
		var r := Game.last_mission_result
		if ctx["type"] == LearningEngine.MISSION_ARENA:
			_check(r.get("score", 0) > 0 and r.get("new_record", false), "l'arène donne un score et un record")
			_check(Game.profile.records.get("arena_score", 0) == r["score"], "record enregistré dans le profil")
		else:
			_check(r.get("boss_beaten", false) and Game.profile.unlocks["crew"].has("crew_2"), "boss vaincu : équipage recruté")
			_check(Game.profile.unlocks["ship_parts"].has("boss_2"), "boss vaincu : pièce de vaisseau")
		m.queue_free()
		await get_tree().process_frame

	# Sauvegarde puis rechargement du profil.
	Game.save()
	var loaded := ProfileStore.load_profile("smoke_test_profile")
	_check(loaded != null and loaded.engine.journal.size() == Game.engine.journal.size(), "profil rechargé à l'identique")
	ProfileStore.delete("smoke_test_profile")

	if _errors.is_empty():
		print("SMOKE OK : %d calculs joués, %d entrées de journal" % [played, Game.engine.journal.size()])
	get_tree().quit(0 if _errors.is_empty() else 1)
