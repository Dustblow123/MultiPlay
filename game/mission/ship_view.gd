class_name ShipView
extends RefCounted
## Dessin du vaisseau en formes grises : coque (couleur achetée), ailes
## (une par boss vaincu, trophées visibles), autocollant.


## Construit les nœuds du vaisseau dans `parent` et retourne la coque.
static func build(parent: Node2D, profile: Profile) -> Polygon2D:
	var parts: int = profile.unlocks["ship_parts"].size()
	for i in range(mini(parts, 4)):
		for side in [-1, 1]:
			var wing := Polygon2D.new()
			var dx := 14 + i * 5
			wing.polygon = PackedVector2Array([Vector2(side * 6, 4 - i * 2), Vector2(side * dx, 12 - i * 2), Vector2(side * 6, 12 - i * 2)])
			wing.color = Color("6b7280")
			parent.add_child(wing)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([Vector2(0, -16), Vector2(14, 12), Vector2(0, 6), Vector2(-14, 12)])
	hull.color = Cosmetics.hull_color(profile)
	parent.add_child(hull)
	var sticker := Cosmetics.sticker(profile)
	if sticker != "":
		var l := UI.label(sticker, 8, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_constant_override("outline_size", 0)
		l.position = Vector2(-6, -4)
		l.size = Vector2(12, 10)
		parent.add_child(l)
	return hull
