class_name ProfileStore
extends RefCounted
## Sauvegarde : un fichier JSON local par profil d'enfant (9), dans user://profiles.

const DIR := "user://profiles"


static func _path(id: String) -> String:
	return "%s/%s.json" % [DIR, id]


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


## Liste des profils : [{id, name, last_played_at, stardust}], le plus récent d'abord.
static func list_profiles() -> Array:
	ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var d := _read_json(DIR + "/" + file)
		if d.is_empty():
			continue
		out.append({
			"id": str(d.get("id", file.get_basename())),
			"name": str(d.get("name", "?")),
			"last_played_at": int(d.get("last_played_at", 0)),
			"stardust": int(d.get("stardust", 0)),
		})
	out.sort_custom(func(a, b): return a["last_played_at"] > b["last_played_at"])
	return out


static func save(profile: Profile) -> bool:
	ensure_dir()
	var f := FileAccess.open(_path(profile.id), FileAccess.WRITE)
	if f == null:
		push_error("Impossible d'écrire le profil %s : %s" % [profile.id, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(profile.to_dict(), "\t"))
	f.close()
	return true


static func load_profile(id: String, cfg: EngineConfig = null) -> Profile:
	var d := _read_json(_path(id))
	if d.is_empty():
		return null
	return Profile.from_dict(d, cfg)


static func delete(id: String) -> void:
	var abs := ProjectSettings.globalize_path(_path(id))
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	push_error("Profil illisible : " + path)
	return {}
