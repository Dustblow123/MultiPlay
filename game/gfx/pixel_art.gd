class_name PixelArt
extends RefCounted
## Pixel art défini en ASCII et converti en textures au démarrage (8, 9) :
## aucun fichier binaire, aucune licence à suivre, rendu net à l'échelle
## entière (filtrage désactivé dans le projet).
##
## Chaque caractère est une couleur de la palette ; « . » est transparent.
## `texture(name, overrides)` remplace des entrées de palette (couleur de coque).

const PALETTE := {
	"h": Color("9ca3af"),  # coque (remplaçable)
	"H": Color("6b7280"),  # coque sombre
	"w": Color("93c5fd"),  # hublot
	"e": Color("fb923c"),  # réacteur
	"E": Color("fde047"),  # réacteur chaud
	"d": Color("4b5563"),  # ennemi
	"D": Color("374151"),  # ennemi sombre
	"r": Color("ef4444"),  # œil / rouge
	"p": Color("7c3aed"),  # Confondeur
	"P": Color("5b21b6"),  # Confondeur sombre
	"f": Color("dc2626"),  # drapeau pirate
	"F": Color("f9fafb"),  # crâne
	"b": Color("7f1d1d"),  # boss
	"B": Color("450a0a"),  # boss sombre
	"c": Color("22c55e"),  # planète (remplaçable)
	"C": Color("15803d"),  # planète ombre
	"l": Color("bbf7d0"),  # planète lumière
	"s": Color("1e3a8a"),  # planète scannée
	"o": Color("000000"),  # contour
}

const SPRITES := {
	"ship": [
		".....h.....",
		"....hhh....",
		"....hhh....",
		"...hHhHh...",
		"...hhhhh...",
		"..hhwhwhh..",
		"..hhhhhhh..",
		".hhhhhhhhh.",
		".hHhhhhhHh.",
		"hhh.hhh.hhh",
		"hh..hhh..hh",
		"h...eEe...h",
		"....eee....",
		".....e.....",
	],
	"wing": [
		"......H",
		".....HH",
		"....HHH",
		"...HHHH",
		"..HHHHH",
		".HHHHHH",
		"HHHHHHH",
	],
	"enemy": [
		"....ddddddd....",
		"..ddddddddddd..",
		".ddd.ddddd.ddd.",
		"ddddrdddddrdddd",
		"dddddddDddddddd",
		".dddDDDDDDDddd.",
		"..dd.......dd..",
		"..d.........d..",
		".d...........d.",
	],
	"pirate": [
		".......ff......",
		".......fFff....",
		".......fFff....",
		".......f.......",
		"....ddddddd....",
		"..ddddddddddd..",
		".ddd.ddddd.ddd.",
		"ddddrdddddrdddd",
		"dddddddDddddddd",
		".dddDDDDDDDddd.",
		"..dd.......dd..",
		"..d.........d..",
	],
	"confondeur": [
		"..ppp.....ppp..",
		".pprpp...pprpp.",
		".ppppp...ppppp.",
		"..ppppppppppp..",
		"..pPPpppppPPp..",
		"..ppppppppppp..",
		"...ppp.....ppp.",
		"..pp.........pp",
	],
	"boss": [
		"........bbbbbbbbb........",
		"......bbbbbbbbbbbbb......",
		"....bbbbBBBBBBBBBbbbb....",
		"...bbbBBrBBBBBBBrBBbbb...",
		"..bbbBBBBBBBBBBBBBBBbbb..",
		".bbbbBBBBBBBBBBBBBBBbbbb.",
		"bbbbbBBBBBBBBBBBBBBBbbbbb",
		"bbbbbbBBBBBBBBBBBBBbbbbbb",
		".bbbbbbbbbbbbbbbbbbbbbbb.",
		"..bbb.bbb.bbbbb.bbb.bbb..",
		"...bb..bb..bbb..bb..bb...",
		"....b...b...b...b...b....",
	],
	"planet": [
		"...ooooo...",
		"..oclllco..",
		".oclllccco.",
		"ocllcccccCo",
		"oclccccccCo",
		"occcccccCCo",
		"occcccccCCo",
		"occccccCCCo",
		".occccCCCo.",
		"..oCCCCCo..",
		"...ooooo...",
	],
	"flag": [
		"f....",
		"fff..",
		"fFf..",
		"fff..",
		"f....",
	],
}

static var _cache: Dictionary = {}


## Texture d'un sprite, avec remplacements de palette éventuels ({"h": Color}).
static func texture(name: String, overrides: Dictionary = {}) -> ImageTexture:
	var key := name
	for k in overrides:
		key += ";%s=%s" % [k, overrides[k].to_html()]
	if _cache.has(key):
		return _cache[key]
	var rows: Array = SPRITES[name]
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, str(row).length())
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var row: String = rows[y]
		for x in range(row.length()):
			var ch: String = row[x]
			if ch == ".":
				continue
			var color: Color = overrides.get(ch, PALETTE.get(ch, Color.MAGENTA))
			image.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


static func sprite(name: String, overrides: Dictionary = {}, scale: float = 2.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture(name, overrides)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(scale, scale)
	return s


## Planète colorée selon son statut (5.1), pour la carte galactique.
static func planet_sprite(status: String, scale: float = 1.0) -> Sprite2D:
	var base: Color = UI.PLANET_COLORS.get(status, UI.PLANET_COLORS["dark"])
	return sprite("planet", {"c": base, "C": base.darkened(0.35), "l": base.lightened(0.45)}, scale)
