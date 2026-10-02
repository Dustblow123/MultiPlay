extends Node
## Autoload « Game » : profil courant, session du moteur, manette et sauvegarde.
## Le jeu ne prend aucune décision pédagogique : il relaie au moteur.

signal controller_disconnected
signal controller_reconnected

## Une nouvelle session du moteur démarre après cette inactivité (2 heures).
const SESSION_TIMEOUT_SEC := 2 * 3600
## Longueur d'une mission (6) : 15 à 25 calculs.
const MISSION_ITEMS := 20
## Bouclier du vaisseau : nombre d'erreurs avant la retraite (échec doux).
const SHIELD_MAX := 3

var profile: Profile
var engine: LearningEngine:
	get:
		return profile.engine if profile != null else null

var paused_for_controller: bool = false
var last_activity_unix: int = 0
var _play_start_unix: int = 0
## Contexte de la mission choisie au hub, lu par la scène de mission.
var mission_context: Dictionary = {"type": "defense"}
## Résultat de la dernière mission, lu par l'écran de fin.
var last_mission_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


# --- Profils -------------------------------------------------------------------

func set_profile(p: Profile) -> void:
	if profile != null and profile != p:
		save()
	profile = p
	_play_start_unix = int(Time.get_unix_time_from_system())
	last_activity_unix = _play_start_unix


func create_profile(name: String) -> Profile:
	var p := Profile.create(name)
	ProfileStore.save(p)
	set_profile(p)
	return p


func load_profile(id: String) -> Profile:
	var p := ProfileStore.load_profile(id)
	if p != null:
		set_profile(p)
	return p


## Charge le profil le plus récent, ou en crée un par défaut (fratrie : plusieurs profils).
func load_or_create_default_profile() -> Profile:
	var profiles := ProfileStore.list_profiles()
	if profiles.is_empty():
		return create_profile("Joueur 1")
	return load_profile(profiles[0]["id"])


func save() -> void:
	if profile == null:
		return
	var now := int(Time.get_unix_time_from_system())
	profile.play_time_sec += maxi(0, now - _play_start_unix)
	_play_start_unix = now
	profile.last_played_at = now
	ProfileStore.save(profile)


# --- Session du moteur -----------------------------------------------------------

## Ouvre une session du moteur si nécessaire (nouveau jour, inactivité, aucune session).
func ensure_session() -> void:
	var now := int(Time.get_unix_time_from_system())
	var today := Profile.today()
	if not engine.session_active or engine.current_day != today or now - last_activity_unix > SESSION_TIMEOUT_SEC:
		engine.start_session(today)
	last_activity_unix = now


func touch() -> void:
	last_activity_unix = int(Time.get_unix_time_from_system())


# --- Manette (9) -------------------------------------------------------------------

func has_controller() -> bool:
	return not Input.get_connected_joypads().is_empty()


func deadzone() -> float:
	return float(profile.settings.get("deadzone", 0.35)) if profile != null else 0.35


func vibration_enabled() -> bool:
	return bool(profile.settings.get("vibration", true)) if profile != null else true


## Courte vibration (8) : seulement sur les bonnes réponses, jamais sur les erreurs.
func vibrate(weak: float = 0.3, strong: float = 0.0, duration: float = 0.12) -> void:
	if not vibration_enabled() or not has_controller():
		return
	Input.start_joy_vibration(Input.get_connected_joypads()[0], weak, strong, duration)


## Pause automatique à la déconnexion de la manette, reprise au rebranchement.
func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and not has_controller():
		paused_for_controller = true
		get_tree().paused = true
		controller_disconnected.emit()
	elif connected and paused_for_controller:
		paused_for_controller = false
		get_tree().paused = false
		controller_reconnected.emit()
