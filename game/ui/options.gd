extends Control
## Options du profil (9) : zone morte du stick pour la roue, vibrations, sons.
## Gauche/Droite modifient la valeur ; la roue de test montre l'effet de la zone morte.

var _nav := MenuNav.new()
var _index: int = 0
var _menu: VBoxContainer
var _wheel_test: Label
var _settings: Dictionary


func _ready() -> void:
	_settings = Game.profile.settings
	UI.fill_background(self)
	var v := UI.vbox(self, Vector2(40, 24), 4)
	v.add_child(UI.label("OPTIONS  ·  %s" % Game.profile.name, 22, UI.ACCENT))
	v.add_child(UI.label("Haut/Bas : choisir   Gauche/Droite : régler   B : retour", 11, UI.MUTED))
	_menu = UI.vbox(self, Vector2(40, 90), 6)
	_wheel_test = UI.label("", 13, UI.MUTED)
	_wheel_test.position = Vector2(40, 250)
	add_child(_wheel_test)
	_refresh()


func _rows() -> Array:
	return [
		{"label": "Zone morte du stick (roue)", "value": "%d %%" % int(round(float(_settings["deadzone"]) * 100))},
		{"label": "Vibrations", "value": "oui" if _settings["vibration"] else "non"},
		{"label": "Sons", "value": "oui" if _settings.get("sound", true) else "non"},
	]


func _refresh() -> void:
	for c in _menu.get_children():
		c.queue_free()
	var rows := _rows()
	for i in range(rows.size()):
		var selected := i == _index
		_menu.add_child(UI.label("%s%-30s  ◀ %s ▶" % ["▶ " if selected else "   ", rows[i]["label"], rows[i]["value"]],
			16, UI.ACCENT if selected else UI.TEXT))


func _adjust(dir: int) -> void:
	match _index:
		0:
			_settings["deadzone"] = clampf(snappedf(float(_settings["deadzone"]) + 0.05 * dir, 0.05), 0.1, 0.8)
		1:
			_settings["vibration"] = not _settings["vibration"]
			if _settings["vibration"]:
				Game.vibrate(0.5, 0.0, 0.2)
		2:
			_settings["sound"] = not _settings.get("sound", true)
			Sfx.enabled = _settings["sound"]
	Sfx.play("select")
	_refresh()


func _process(delta: float) -> void:
	var dir := _nav.poll_vertical(delta)
	if dir != 0:
		_index = (_index + dir + _rows().size()) % _rows().size()
		Sfx.play("select")
		_refresh()
	var h := _nav.poll_horizontal(delta)
	if h != 0:
		_adjust(h)
	if _nav.back() or _nav.confirm():
		Game.save()
		get_tree().change_scene_to_file("res://game/hub.tscn")
	_update_wheel_test()


## Roue de test : affiche le chiffre que la zone morte laisserait passer.
func _update_wheel_test() -> void:
	if not Game.has_controller():
		_wheel_test.text = "Branche une manette pour tester la roue au stick droit."
		return
	var device: int = Input.get_connected_joypads()[0]
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if v.length() < float(_settings["deadzone"]):
		_wheel_test.text = "Test de la roue (stick droit) : au repos  (inclinaison %d %%)" % int(v.length() * 100)
	else:
		var angle := fposmod(v.angle() + PI / 2, TAU)
		var digit := int(round(angle / (TAU / 10.0))) % 10
		_wheel_test.text = "Test de la roue (stick droit) : chiffre %d  (inclinaison %d %%)" % [digit, int(v.length() * 100)]
