extends Control
## Hub (vaisseau-mère) : carte galactique, suggestion du moteur et choix de mission (2, 5, 8).
## Le moteur « suggère » la mission utile sans que cela ressemble à un devoir.

var _options: Array = []
var _index: int = 0
var _menu: VBoxContainer
var _engine: LearningEngine


func _ready() -> void:
	if Game.profile == null:
		Game.load_or_create_default_profile()
	Game.ensure_session()
	_engine = Game.engine
	UI.fill_background(self)
	_build_header()
	_build_galaxy_map()
	_build_options()
	_menu = UI.vbox(self, Vector2(360, 96), 2)
	_refresh_menu()
	var help := UI.label("Haut/Bas : choisir   A : lancer   P / Retour : écran parent", 11, UI.MUTED)
	help.position = Vector2(24, 338)
	add_child(help)


func _build_header() -> void:
	var v := UI.vbox(self, Vector2(24, 14), 2)
	v.add_child(UI.label("VAISSEAU-MÈRE  ·  %s" % Game.profile.name, 20, UI.ACCENT))
	var counts := _engine.counts_by_state()
	v.add_child(UI.label("Planètes colonisées : %d / %d     ✦ %d     Session %d" % [
		counts["mastered"], _engine.states.size(), Game.profile.stardust, _engine.session_id], 12, UI.MUTED))


## Carte galactique (5.1) : une ligne par système, un carré par planète.
func _build_galaxy_map() -> void:
	var map := _engine.galaxy_map()
	var v := UI.vbox(self, Vector2(24, 60), 3)
	v.add_child(UI.label("CARTE GALACTIQUE", 14, UI.TEXT))
	for table in _engine.config.table_order:
		if not map.has(table):
			continue
		var system: Dictionary = map[table]
		var h := UI.hbox(v, 3)
		var name := UI.label("×%-2d" % table, 14, UI.TEXT)
		name.custom_minimum_size = Vector2(36, 0)
		h.add_child(name)
		for key in system["facts"]:
			var planet: Dictionary = system["facts"][key]
			var cell := UI.rect(UI.PLANET_COLORS[planet["status"]], Vector2(14, 14))
			if planet["due"]:
				# Planète attaquée par les pirates : contour clair.
				var outline := UI.rect(Color.WHITE, Vector2(16, 16))
				outline.add_child(cell)
				cell.position = Vector2(1, 1)
				h.add_child(outline)
			else:
				h.add_child(cell)
		var status := "%d/%d" % [system["colonized"], system["total"]]
		if system["complete"]:
			status += "  BOSS prêt" if not _boss_beaten(table) else "  libéré"
		elif system["due"] > 0:
			status += "  ⚠ %d" % system["due"]
		h.add_child(UI.label(status, 12, UI.MUTED))
	var legend := UI.hbox(v, 8)
	for entry in [["sombre", "dark"], ["en orbite", "orbit"], ["colonisée", "colonized"], ["assiégée", "besieged"]]:
		var h2 := UI.hbox(legend, 3)
		h2.add_child(UI.rect(UI.PLANET_COLORS[entry[1]], Vector2(10, 10)))
		h2.add_child(UI.label(entry[0], 10, UI.MUTED))


func _boss_beaten(table: int) -> bool:
	return Game.profile.unlocks["ship_parts"].has("boss_%d" % table)


func _build_options() -> void:
	_options = []
	var suggestion := _engine.suggest_mission()
	var reason := ""
	match suggestion.get("reason", ""):
		"pirates":
			reason = "Les pirates attaquent %d planète(s) !" % suggestion.get("due", 0)
		"new_facts":
			reason = "De nouvelles planètes sont à portée."
		"confusion":
			reason = "Le Confondeur rôde près de %s et %s." % [UI.fact_text(suggestion["pair"][0]), UI.fact_text(suggestion["pair"][1])]
		"fun":
			reason = "La flotte est calme : place à l'arène !"
	var ctx := {"type": suggestion["type"]}
	if suggestion.has("pair"):
		ctx["pair"] = suggestion["pair"]
	_options.append({"label": "Mission suggérée : " + UI.mission_name(suggestion["type"]), "hint": reason, "context": ctx})
	_options.append({"label": "Défense", "hint": "Repousser les pirates des planètes attaquées.", "context": {"type": LearningEngine.MISSION_DEFENSE}})
	_options.append({"label": "Exploration", "hint": "Découvrir 2 ou 3 planètes nouvelles.", "context": {"type": LearningEngine.MISSION_EXPLORATION}})
	if _engine.counts_by_state()["mastered"] >= 5:
		_options.append({"label": "Arène", "hint": "Faits maîtrisés seulement : score et combos.", "context": {"type": LearningEngine.MISSION_ARENA}})
	for table in _engine.config.table_order:
		if _engine.boss_ready(table) and not _boss_beaten(table):
			_options.append({"label": "Boss du système ×%d" % table, "hint": _boss_name(table),
				"context": {"type": LearningEngine.MISSION_BOSS, "tables": [table], "boss": true}})
	_options.append({"label": "Écran parent", "hint": "Grille des faits, confusions, temps de jeu.", "scene": "res://game/ui/parent_screen.tscn"})
	_options.append({"label": "Changer de profil", "hint": "", "scene": "res://game/main.tscn"})


## Boss par table (7).
static func _boss_name(table: int) -> String:
	match table:
		2: return "Les Jumeaux : ×2, c'est doubler."
		4: return "Le Double-Jumeau : ×4, c'est doubler deux fois."
		5: return "L'Étoile à cinq branches : les résultats finissent par 0 ou 5."
		9: return "Le Miroir : les chiffres du résultat font 9."
		7, 8: return "Les Généraux : les tables les plus dures."
		1, 10: return "Le Gardien du système d'origine."
	return "Gardien du système ×%d." % table


func _refresh_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()
	_menu.add_child(UI.label("MISSIONS", 14, UI.TEXT))
	for i in range(_options.size()):
		var o: Dictionary = _options[i]
		var selected := i == _index
		_menu.add_child(UI.label(("▶ " if selected else "   ") + o["label"], 15, UI.ACCENT if selected else UI.TEXT))
	var hint: String = _options[_index].get("hint", "")
	var l := UI.label(hint, 11, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(260, 0)
	_menu.add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_bas"):
		_index = (_index + 1) % _options.size()
		_refresh_menu()
	elif event.is_action_pressed("menu_haut"):
		_index = (_index - 1 + _options.size()) % _options.size()
		_refresh_menu()
	elif event.is_action_pressed("canon_A") or event.is_action_pressed("tir"):
		_launch(_options[_index])
	elif event.is_action_pressed("ecran_parent"):
		get_tree().change_scene_to_file("res://game/ui/parent_screen.tscn")


func _launch(option: Dictionary) -> void:
	if option.has("scene"):
		Game.save()
		get_tree().change_scene_to_file(option["scene"])
		return
	Game.mission_context = option["context"]
	get_tree().change_scene_to_file("res://game/mission/mission.tscn")
