extends Control
## Personnalisation du vaisseau (2, 5.3) : cosmétiques achetés en poussière
## d'étoile, pièces de vaisseau et équipage gagnés sur les boss.

var _nav := MenuNav.new()
var _index: int = 0
var _menu: VBoxContainer
var _ship_preview: Node2D
var _message: Label
var _rows: Array = []


func _ready() -> void:
	UI.fill_background(self)
	var v := UI.vbox(self, Vector2(24, 14), 2)
	v.add_child(UI.label("VAISSEAU ET ÉQUIPAGE  ·  %s" % Game.profile.name, 20, UI.ACCENT))
	v.add_child(UI.label("Haut/Bas : choisir   A : acheter ou équiper   B : retour", 11, UI.MUTED))
	_menu = UI.vbox(self, Vector2(24, 62), 1)
	_message = UI.label("", 12, UI.MUTED)
	_message.position = Vector2(24, 338)
	add_child(_message)
	_ship_preview = Node2D.new()
	_ship_preview.position = Vector2(500, 120)
	_ship_preview.scale = Vector2(3, 3)
	add_child(_ship_preview)
	_build_rows()
	_refresh()


func _build_rows() -> void:
	_rows = []
	for id in Cosmetics.HULL_COLORS:
		_rows.append({"category": "color", "id": id, "label": Cosmetics.HULL_COLORS[id]["label"], "price": Cosmetics.HULL_COLORS[id]["price"], "setting": "ship_color"})
	for id in Cosmetics.TRAILS:
		_rows.append({"category": "trail", "id": id, "label": Cosmetics.TRAILS[id]["label"], "price": Cosmetics.TRAILS[id]["price"], "setting": "ship_trail"})
	for id in Cosmetics.STICKERS:
		_rows.append({"category": "sticker", "id": id, "label": Cosmetics.STICKERS[id]["label"], "price": Cosmetics.STICKERS[id]["price"], "setting": "ship_sticker"})


func _refresh() -> void:
	for c in _menu.get_children():
		c.queue_free()
	_menu.add_child(UI.label("Poussière d'étoile : ✦ %d" % Game.profile.stardust, 14, UI.ACCENT))
	var last_category := ""
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		if r["category"] != last_category:
			last_category = r["category"]
			_menu.add_child(UI.label({"color": "Couleur de coque", "trail": "Traînée", "sticker": "Autocollant"}[last_category], 12, UI.TEXT))
		var owned := Cosmetics.owned(Game.profile, r["category"], r["id"])
		var equipped: bool = str(Game.profile.settings.get(r["setting"], "grey" if r["category"] == "color" else "none")) == r["id"]
		var status := "équipé" if equipped else ("acquis" if owned else "✦ %d" % r["price"])
		var selected := i == _index
		_menu.add_child(UI.label("%s%-22s %s" % ["▶ " if selected else "   ", r["label"], status], 13,
			UI.ACCENT if selected else (UI.TEXT if owned else UI.MUTED)))
	_draw_ship()
	_build_trophies()


func _draw_ship() -> void:
	for c in _ship_preview.get_children():
		c.queue_free()
	ShipView.build(_ship_preview, Game.profile)


func _build_trophies() -> void:
	var old := get_node_or_null("Trophies")
	if old != null:
		old.free()
	var v := UI.vbox(self, Vector2(380, 190), 2)
	v.name = "Trophies"
	var parts: Array = Game.profile.unlocks["ship_parts"]
	v.add_child(UI.label("Pièces de vaisseau : %d" % parts.size(), 13, UI.TEXT))
	v.add_child(UI.label("Une aile par système libéré." if not parts.is_empty() else "Bats un boss pour gagner une aile.", 11, UI.MUTED))
	v.add_child(UI.label(" ", 4))
	var crew: Array = Game.profile.unlocks["crew"]
	v.add_child(UI.label("Équipage : %d" % crew.size(), 13, UI.TEXT))
	if crew.is_empty():
		v.add_child(UI.label("Libère un système pour recruter.", 11, UI.MUTED))
	for id in crew:
		v.add_child(UI.label("• " + Crew.name_of(Crew.table_of(id)), 11, UI.MUTED))


func _process(delta: float) -> void:
	var dir := _nav.poll_vertical(delta)
	if dir != 0:
		_index = (_index + dir + _rows.size()) % _rows.size()
		Sfx.play("select")
		_refresh()
	elif _nav.confirm():
		var r: Dictionary = _rows[_index]
		if Cosmetics.buy_or_equip(Game.profile, r["category"], r["id"]):
			Sfx.play("combo")
			_message.text = "%s équipé." % r["label"]
			Game.save()
		else:
			Sfx.play("error")
			_message.text = "Il manque de la poussière d'étoile : chaque bonne réponse en rapporte."
		_refresh()
	elif _nav.back():
		Game.save()
		get_tree().change_scene_to_file("res://game/hub.tscn")
