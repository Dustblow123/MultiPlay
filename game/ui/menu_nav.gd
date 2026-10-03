class_name MenuNav
extends RefCounted
## Navigation de menu à la manette, par sondage (et non par événements) :
## un stick analogique génère des rafales d'événements autour du seuil, ce qui
## rendait les menus trop sensibles. Ici : détection de front, répétition
## temporisée quand on maintient, retour au neutre obligatoire à l'ouverture
## d'un écran, et délai de grâce avant d'accepter une validation.
##
## Usage, dans `_process(delta)` d'un écran :
##   var dir := nav.poll_vertical(delta)   # -1, 0 ou +1
##   if nav.confirm(): ...
##   if nav.back(): ...

const DEADZONE := 0.5
const REPEAT_DELAY := 0.45
const REPEAT_INTERVAL := 0.18
const GRACE_SEC := 0.3

var _axes: Dictionary = {}
var _age: float = 0.0


func _axis_state(name: String) -> Dictionary:
	if not _axes.has(name):
		_axes[name] = {"dir": 0, "held": 0.0, "neutral_seen": false}
	return _axes[name]


func poll_vertical(delta: float) -> int:
	_age += delta
	return _poll("vertical", "menu_haut", "menu_bas", delta)


func poll_horizontal(delta: float) -> int:
	return _poll("horizontal", "deplacer_gauche", "deplacer_droite", delta)


func _poll(name: String, negative: String, positive: String, delta: float) -> int:
	var s := _axis_state(name)
	var axis := Input.get_action_strength(positive) - Input.get_action_strength(negative)
	var dir := 0
	if axis > DEADZONE:
		dir = 1
	elif axis < -DEADZONE:
		dir = -1
	if dir == 0:
		s["neutral_seen"] = true
		s["dir"] = 0
		s["held"] = 0.0
		return 0
	if not s["neutral_seen"]:
		# Stick déjà incliné à l'ouverture de l'écran : on attend qu'il revienne au centre.
		return 0
	if dir != s["dir"]:
		s["dir"] = dir
		s["held"] = 0.0
		return dir
	s["held"] += delta
	if s["held"] >= REPEAT_DELAY:
		s["held"] -= REPEAT_INTERVAL
		return dir
	return 0


## Validation (A, Entrée, Espace), ignorée pendant le délai de grâce qui suit
## l'ouverture de l'écran pour qu'un appui venu de l'écran précédent ne compte pas.
func confirm() -> bool:
	return _age >= GRACE_SEC and Input.is_action_just_pressed("menu_valider")


func back() -> bool:
	return _age >= GRACE_SEC and Input.is_action_just_pressed("menu_retour")


func pressed(action: String) -> bool:
	return _age >= GRACE_SEC and Input.is_action_just_pressed(action)
