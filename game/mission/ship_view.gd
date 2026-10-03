class_name ShipView
extends RefCounted
## Dessin du vaisseau en pixel art : coque (couleur achetée), ailes (une par
## boss vaincu, trophées visibles), autocollant.

const SCALE := 2.0


## Construit les nœuds du vaisseau dans `parent` et retourne la coque.
static func build(parent: Node2D, profile: Profile) -> Sprite2D:
	var parts: int = profile.unlocks["ship_parts"].size()
	for i in range(mini(parts, 4)):
		for side in [-1, 1]:
			var wing := PixelArt.sprite("wing", {}, SCALE)
			wing.flip_h = side < 0
			wing.position = Vector2(side * (12 + i * 4), 8 - i * 3)
			parent.add_child(wing)
	var hull := PixelArt.sprite("ship", {"h": Cosmetics.hull_color(profile), "H": Cosmetics.hull_color(profile).darkened(0.3)}, SCALE)
	parent.add_child(hull)
	var sticker := Cosmetics.sticker(profile)
	if sticker != "":
		var l := UI.label(sticker, 8, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_constant_override("outline_size", 0)
		l.position = Vector2(-6, -4)
		l.size = Vector2(12, 10)
		parent.add_child(l)
	return hull
