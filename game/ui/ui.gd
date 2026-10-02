class_name UI
extends RefCounted
## Petits constructeurs d'interface pour le prototype (formes grises, aucun asset).
## Règle absolue (8) : les nombres restent lisibles depuis le canapé.

const BG := Color("0b1020")
const STAR := Color(0.55, 0.6, 0.75, 0.55)
const TEXT := Color("e5e7eb")
const MUTED := Color("9ca3af")
const ACCENT := Color("fde047")
const OK := Color("22c55e")
const BAD := Color("ef4444")
const GREY := Color("9ca3af")
const DARK_GREY := Color("4b5563")

## Couleurs des boutons Xbox (A vert, B rouge, X bleu, Y jaune), lettre affichée pour les daltoniens.
const BUTTON_COLORS := {"A": Color("2ecc71"), "B": Color("e74c3c"), "X": Color("3498db"), "Y": Color("f1c40f")}
const BUTTON_ORDER := ["A", "B", "X", "Y"]
const BUTTON_ACTIONS := {"A": "canon_A", "B": "canon_B", "X": "canon_X", "Y": "canon_Y"}

## Couleurs des planètes sur la carte (5.1).
const PLANET_COLORS := {
	"dark": Color("374151"),
	"orbit": Color("f59e0b"),
	"colonized": Color("22c55e"),
	"besieged": Color("ef4444"),
}


static func label(text: String, size: int = 16, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4 if size >= 20 else 2)
	l.horizontal_alignment = align
	return l


static func big_number(text: String, size: int = 28, color: Color = TEXT) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6)
	return l


static func rect(color: Color, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = size
	r.size = size
	return r


static func fill_background(parent: Control, color: Color = BG) -> void:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)


static func vbox(parent: Node, pos: Vector2, separation: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v


static func hbox(parent: Node, separation: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	parent.add_child(h)
	return h


## Nom lisible d'un fait : "7 × 8".
static func fact_text(key: String) -> String:
	var f := Fact.from_key(key)
	return "%d × %d" % [f.a, f.b]


static func mission_name(type: String) -> String:
	match type:
		LearningEngine.MISSION_EXPLORATION:
			return "Exploration"
		LearningEngine.MISSION_DEFENSE:
			return "Défense"
		LearningEngine.MISSION_DUEL:
			return "Duel contre le Confondeur"
		LearningEngine.MISSION_ARENA:
			return "Arène"
		LearningEngine.MISSION_BOSS:
			return "Boss"
	return type.capitalize()


static func format_duration(sec: int) -> String:
	var h := sec / 3600
	var m := (sec % 3600) / 60
	if h > 0:
		return "%d h %02d min" % [h, m]
	return "%d min" % m
