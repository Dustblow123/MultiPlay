class_name Cosmetics
extends RefCounted
## Catalogue des cosmétiques (5.3) : achetés en poussière d'étoile, ils ne
## donnent aucun avantage. Les pièces de vaisseau et l'équipage, eux, sont des
## trophées de boss et ne s'achètent pas.

const HULL_COLORS := {
	"grey": {"label": "Gris de série", "price": 0, "color": Color("9ca3af")},
	"blue": {"label": "Bleu nébuleuse", "price": 20, "color": Color("60a5fa")},
	"green": {"label": "Vert comète", "price": 20, "color": Color("4ade80")},
	"orange": {"label": "Orange solaire", "price": 30, "color": Color("fb923c")},
	"violet": {"label": "Violet pulsar", "price": 40, "color": Color("c084fc")},
	"gold": {"label": "Or galactique", "price": 80, "color": Color("fde047")},
}

const TRAILS := {
	"none": {"label": "Aucune traînée", "price": 0},
	"sparks": {"label": "Étincelles", "price": 40},
	"stars": {"label": "Poussière d'étoile", "price": 60},
}

const STICKERS := {
	"none": {"label": "Aucun autocollant", "price": 0, "text": ""},
	"star": {"label": "Étoile", "price": 15, "text": "★"},
	"heart": {"label": "Cœur", "price": 15, "text": "♥"},
	"bolt": {"label": "Éclair", "price": 25, "text": "⚡"},
}


static func hull_color(profile: Profile) -> Color:
	var id: String = str(profile.settings.get("ship_color", "grey"))
	return HULL_COLORS.get(id, HULL_COLORS["grey"])["color"]


static func trail(profile: Profile) -> String:
	return str(profile.settings.get("ship_trail", "none"))


static func sticker(profile: Profile) -> String:
	var id: String = str(profile.settings.get("ship_sticker", "none"))
	return STICKERS.get(id, STICKERS["none"])["text"]


static func owned(profile: Profile, category: String, id: String) -> bool:
	return id in ["grey", "none"] or profile.unlocks["cosmetics"].has("%s:%s" % [category, id])


## Achète (si nécessaire) puis équipe un cosmétique. Retourne false si la
## poussière d'étoile manque.
static func buy_or_equip(profile: Profile, category: String, id: String) -> bool:
	var catalog: Dictionary = {"color": HULL_COLORS, "trail": TRAILS, "sticker": STICKERS}[category]
	if not owned(profile, category, id):
		var price: int = catalog[id]["price"]
		if profile.stardust < price:
			return false
		profile.stardust -= price
		profile.unlocks["cosmetics"].append("%s:%s" % [category, id])
	var setting: String = {"color": "ship_color", "trail": "ship_trail", "sticker": "ship_sticker"}[category]
	profile.settings[setting] = id
	return true
