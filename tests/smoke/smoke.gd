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
	await get_tree().process_frame

	# Sauvegarde puis rechargement du profil.
	Game.save()
	var loaded := ProfileStore.load_profile("smoke_test_profile")
	_check(loaded != null and loaded.engine.journal.size() == Game.engine.journal.size(), "profil rechargé à l'identique")
	ProfileStore.delete("smoke_test_profile")

	if _errors.is_empty():
		print("SMOKE OK : %d calculs joués, %d entrées de journal" % [played, Game.engine.journal.size()])
	get_tree().quit(0 if _errors.is_empty() else 1)
