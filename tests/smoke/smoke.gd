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
			if m.phase == m.Phase.ACTIVE and not m._wave.is_empty():
				for w in m._wave:
					w["start_ms"] = Time.get_ticks_msec() - 1500
					_check(w["item"]["state"] == "mastered", "nuée : faits maîtrisés seulement")
					m._ship.position.x = w["node"].position.x
					for ch in str(w["item"]["answer"]):
						m.wheel_add_digit(int(ch))
					m.wheel_fire()
			elif m.phase == m.Phase.ACTIVE:
				var it: Dictionary = m.item
				_check(it["state"] == "mastered", "%s : faits maîtrisés seulement" % ctx["type"])
				m._item_start_ms = Time.get_ticks_msec() - 1500
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

	# Défense : des planètes attaquées (révisions dues) et le panneau de planète.
	for key in ["3x4", "3x5", "4x5"]:
		var fs2: FactState = Game.engine.states[key]
		fs2.state = FactState.State.CONSOLIDATION
		fs2.box = 2
		fs2.due_session = 0
		fs2.due_day = 0
	Game.mission_context = {"type": LearningEngine.MISSION_DEFENSE}
	var defense: Node = load("res://game/mission/mission.tscn").instantiate()
	add_child(defense)
	await get_tree().process_frame
	_check(defense.item.get("is_due", false), "la défense sert d'abord une planète attaquée")
	_check(defense._planet_label.text.begins_with("Pirates"), "le panneau annonce les pirates")
	defense.queue_free()
	await get_tree().process_frame

	# Pixel art : chaque sprite se convertit en texture, sans pixel magenta (couleur inconnue).
	for name in PixelArt.SPRITES:
		var tex := PixelArt.texture(name)
		_check(tex.get_width() > 0 and tex.get_height() > 0, "texture vide : " + name)
		var img := tex.get_image()
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				_check(img.get_pixel(x, y) != Color.MAGENTA, "caractère inconnu dans le sprite " + name)
	_check(PixelArt.texture("ship", {"h": Color.RED}).get_image().get_pixel(5, 0) == Color.RED, "la couleur de coque se remplace")

	# Nuée rapide : plusieurs faits maîtrisés à la fois, tir du nombre composé sur l'ennemi aligné.
	Game.mission_context = {"type": LearningEngine.MISSION_ARENA}
	var wave_mission: Node = load("res://game/mission/mission.tscn").instantiate()
	add_child(wave_mission)
	await get_tree().process_frame
	_check(wave_mission._wave.size() >= 2, "en arène, les faits maîtrisés arrivent en nuée (obtenu %d)" % wave_mission._wave.size())
	if wave_mission._wave.size() >= 2:
		var consumed: int = wave_mission.item_index
		_check(consumed == wave_mission._wave.size(), "la nuée consomme autant d'items que d'ennemis")
		for w in wave_mission._wave:
			w["start_ms"] = Time.get_ticks_msec() - 2000
		var first: Dictionary = wave_mission._wave[0]
		wave_mission._ship.position.x = first["node"].position.x
		for ch in str(int(first["item"]["answer"]) + 1):
			wave_mission.wheel_add_digit(int(ch))
		wave_mission.wheel_fire()
		_check(not first["done"] and first["wrong"] and wave_mission.shield == Game.SHIELD_MAX - 1, "mauvais nombre : ennemi renforcé, bouclier -1")
		for w in wave_mission._wave:
			wave_mission._ship.position.x = w["node"].position.x
			for ch in str(w["item"]["answer"]):
				wave_mission.wheel_add_digit(int(ch))
			wave_mission.wheel_fire()
		_check(wave_mission.phase == wave_mission.Phase.FEEDBACK, "nuée repoussée quand tous les ennemis sont abattus")
		_check(Game.engine.journal[-1].get("variant", "") == "wave", "la nuée est journalisée")
	wave_mission.queue_free()
	await get_tree().process_frame

	# Calcul inversé : nuée de 4 nombres, tir aligné, raté sans pénalité.
	for key in ["3x6", "4x6", "6x7"]:
		var fs3: FactState = Game.engine.states[key]
		fs3.state = FactState.State.LEARNING
		fs3.box = 3
	Game.mission_context = {"type": LearningEngine.MISSION_EXPLORATION}
	var inv: Node = load("res://game/mission/mission.tscn").instantiate()
	add_child(inv)
	await get_tree().process_frame
	var tries := 0
	while not (inv.phase == inv.Phase.ACTIVE and inv.item["mode"] == LearningEngine.MODE_QCM and inv.item["box"] >= 2) and tries < 40:
		tries += 1
		if inv.phase == inv.Phase.ACTIVE:
			inv._report(inv.item["answer"], {})
			inv._resolve(true, "", false)
		for _i in range(3):
			inv._process(0.3)
			await get_tree().process_frame
	if inv.phase == inv.Phase.ACTIVE:
		inv.item["box"] = 3
		inv._inverted = true
		inv._start_inverted_wave()
		_check(inv._ship_label.visible and inv._swarm[0].visible, "le vaisseau porte le calcul, la nuée les nombres")
		var shield_before: int = inv.shield
		inv._ship.position.x = 5.0  # loin de tout ennemi
		inv.fire_inverted()
		_check(inv.phase == inv.Phase.ACTIVE and inv.shield == shield_before, "un tir dans le vide ne coûte rien")
		var correct_index: int = inv._swarm_values.find(inv.item["answer"])
		inv._ship.position.x = inv._swarm[correct_index].position.x
		inv._item_start_ms = Time.get_ticks_msec() - 1500  # au-delà du seuil anti-hasard
		inv.fire_inverted()
		_check(inv.phase == inv.Phase.FEEDBACK and inv.combo >= 1, "tir aligné sur le bon nombre : réussite")
		_check(Game.engine.journal[-1].get("variant", "") == "inverted", "la variante est journalisée")
	else:
		_check(false, "aucun item QCM obtenu pour tester le calcul inversé")
	inv.queue_free()
	await get_tree().process_frame

	# Sauvegarde puis rechargement du profil.
	Game.save()
	var loaded := ProfileStore.load_profile("smoke_test_profile")
	_check(loaded != null and loaded.engine.journal.size() == Game.engine.journal.size(), "profil rechargé à l'identique")
	ProfileStore.delete("smoke_test_profile")

	if _errors.is_empty():
		print("SMOKE OK : %d calculs joués, %d entrées de journal" % [played, Game.engine.journal.size()])
	get_tree().quit(0 if _errors.is_empty() else 1)
