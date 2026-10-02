class_name Profile
extends RefCounted
## Profil d'un enfant (couche persistance) : identité, réglages, déblocages et
## moteur d'apprentissage avec son journal brut.

const SAVE_VERSION := 1

var id: String = ""
var name: String = ""
var created_at: int = 0
var last_played_at: int = 0
var play_time_sec: int = 0
## Poussière d'étoile (5.3) : gagnée à chaque bonne réponse, sert aux cosmétiques.
var stardust: int = 0
var settings: Dictionary = {"deadzone": 0.35, "vibration": true}
var unlocks: Dictionary = {"weapons": ["cannons"], "ship_parts": [], "crew": [], "cosmetics": []}
var engine: LearningEngine


static func create(profile_name: String, cfg: EngineConfig = null) -> Profile:
	var p := Profile.new()
	p.id = "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	p.name = profile_name
	p.created_at = int(Time.get_unix_time_from_system())
	p.engine = LearningEngine.new(cfg)
	return p


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"id": id,
		"name": name,
		"created_at": created_at,
		"last_played_at": last_played_at,
		"play_time_sec": play_time_sec,
		"stardust": stardust,
		"settings": settings.duplicate(true),
		"unlocks": unlocks.duplicate(true),
		"engine": engine.to_dict(),
	}


static func from_dict(d: Dictionary, cfg: EngineConfig = null) -> Profile:
	var p := Profile.new()
	p.id = str(d.get("id", ""))
	p.name = str(d.get("name", ""))
	p.created_at = int(d.get("created_at", 0))
	p.last_played_at = int(d.get("last_played_at", 0))
	p.play_time_sec = int(d.get("play_time_sec", 0))
	p.stardust = int(d.get("stardust", 0))
	p.settings = d.get("settings", {}).duplicate(true)
	for k in ["deadzone", "vibration"]:
		if not p.settings.has(k):
			p.settings[k] = {"deadzone": 0.35, "vibration": true}[k]
	p.unlocks = d.get("unlocks", {}).duplicate(true)
	for k in ["weapons", "ship_parts", "crew", "cosmetics"]:
		if not p.unlocks.has(k):
			p.unlocks[k] = []
	p.engine = LearningEngine.from_dict(d.get("engine", {}), cfg)
	return p


## Jour courant (nombre de jours depuis l'époque, heure locale) pour le moteur.
static func today() -> int:
	var unix := Time.get_unix_time_from_system()
	var offset: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(floor((unix + offset) / 86400.0))
