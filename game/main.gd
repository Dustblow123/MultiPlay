extends Control
## Écran d'accueil : choix du profil (plusieurs profils pour une fratrie), puis hub.

var _profiles: Array = []
var _index: int = 0
var _list: VBoxContainer


func _ready() -> void:
	UI.fill_background(self)
	var v := UI.vbox(self, Vector2(40, 24), 6)
	v.add_child(UI.label("CONQUÊTE DES TABLES", 30, UI.ACCENT))
	v.add_child(UI.label("Prototype · formes grises, aucun asset", 12, UI.MUTED))
	v.add_child(UI.label(" ", 8))
	v.add_child(UI.label("Qui joue ?", 18))
	_list = UI.vbox(self, Vector2(40, 120), 2)
	var help := UI.label("Haut/Bas : choisir    A : jouer    Clavier : flèches, lettres A B X Y, Espace, Entrée", 11, UI.MUTED)
	help.position = Vector2(40, 330)
	add_child(help)
	_refresh()


func _refresh() -> void:
	_profiles = ProfileStore.list_profiles()
	for c in _list.get_children():
		c.queue_free()
	for i in range(_profiles.size()):
		var p: Dictionary = _profiles[i]
		var text := "%s   ✦ %d" % [p["name"], p["stardust"]]
		_list.add_child(_entry(text, i))
	_list.add_child(_entry("+ Nouveau profil", _profiles.size()))


func _entry(text: String, i: int) -> Label:
	var selected := i == _index
	var l := UI.label(("▶ " if selected else "   ") + text, 18, UI.ACCENT if selected else UI.TEXT)
	return l


func _unhandled_input(event: InputEvent) -> void:
	var count := _profiles.size() + 1
	if event.is_action_pressed("menu_bas"):
		_index = (_index + 1) % count
		_refresh()
	elif event.is_action_pressed("menu_haut"):
		_index = (_index - 1 + count) % count
		_refresh()
	elif event.is_action_pressed("canon_A") or event.is_action_pressed("tir"):
		_confirm()


func _confirm() -> void:
	if _index < _profiles.size():
		Game.load_profile(_profiles[_index]["id"])
	else:
		Game.create_profile("Joueur %d" % (_profiles.size() + 1))
	get_tree().change_scene_to_file("res://game/hub.tscn")
