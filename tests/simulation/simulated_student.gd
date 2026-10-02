class_name SimulatedStudent
extends RefCounted
## Élève fictif qui oublie selon une courbe exponentielle (4.10 : « le moteur se
## valide seul, par simulation d'élèves fictifs qui oublient selon une courbe »).
##
## Modèle : chaque fait a une stabilité (en jours). La probabilité de rappel
## après un écart de `gap` jours vaut exp(-gap / stabilité). Un rappel réussi
## renforce la stabilité (effet d'espacement), un échec la réduit mais le
## retour immédiat du jeu réapprend le fait.

var rng := RandomNumberGenerator.new()
## 0.6 = élève lent, 1.0 = moyen, 1.4 = rapide.
var ability: float = 1.0
## Temps physique pour viser et composer, indépendant du savoir (4.4).
var motor_base: Dictionary = {"qcm": 900, "wheel": 2200, "decomposition": 2600}
## Confusions persistantes : clé du fait -> mauvaise réponse typique.
var confusions: Dictionary = {}
## Mémoire : clé -> {"stability": jours, "last_day": jour}.
var memory: Dictionary = {}
var slip_rate: float = 0.03


func _init(seed: int, p_ability: float = 1.0, p_confusions: Dictionary = {}, p_motor: Dictionary = {}) -> void:
	rng.seed = seed
	ability = p_ability
	confusions = p_confusions
	for k in p_motor:
		motor_base[k] = p_motor[k]


## Connaissance avant tout enseignement : les faits triviaux sont connus,
## les petites tables à moitié, les autres presque pas.
func _prior_stability(f: Fact) -> float:
	if f.is_trivial():
		return 60.0
	if f.a <= 2 or f.b <= 2 or f.a == 5 or f.b == 5:
		return 1.5 * ability
	return 0.2 * ability


func _memory_of(key: String, day: int) -> Dictionary:
	if not memory.has(key):
		memory[key] = {"stability": _prior_stability(Fact.from_key(key)), "last_day": float(day) - 1.0}
	return memory[key]


func recall_probability(key: String, day: int) -> float:
	var m := _memory_of(key, day)
	var gap: float = maxf(0.0, float(day) - float(m["last_day"]))
	var p: float = exp(-gap / float(m["stability"]))
	if confusions.has(key):
		p *= 0.8
	return clampf(p, 0.0, 1.0 - slip_rate)


func answer(item: Dictionary, day: int) -> Dictionary:
	var key: String = item["fact"]
	var mode: String = item["mode"]
	if mode == LearningEngine.MODE_PRESENTATION:
		memory[key] = {"stability": 1.0 * ability, "last_day": float(day)}
		return {"given": item["answer"], "time_ms": 0}

	var p := recall_probability(key, day)
	var success := rng.randf() < p
	var base: int = motor_base.get(mode, 2000)
	if success:
		_reinforce(key, day, p)
		var time := base + int((1.0 - p) * 3500.0) + rng.randi_range(-200, 300)
		return {"given": item["accepted"][0], "time_ms": maxi(350, time)}

	var given := _wrong_answer(item, key)
	_relearn(key, day)
	return {"given": given, "time_ms": base + 2500 + rng.randi_range(0, 1500)}


func _wrong_answer(item: Dictionary, key: String) -> int:
	var answer: int = item["answer"]
	if item["mode"] == LearningEngine.MODE_QCM:
		var options: Array = item["options"]
		if confusions.has(key) and options.has(confusions[key]):
			return confusions[key]
		var wrong: Array = []
		for o in options:
			if not item["accepted"].has(o):
				wrong.append(o)
		return wrong[rng.randi_range(0, wrong.size() - 1)]
	if confusions.has(key):
		return confusions[key]
	var f := Fact.from_key(key)
	return answer + (f.a if rng.randf() < 0.5 else -f.b)


## Rappel réussi : la stabilité croît d'autant plus que l'écart était grand.
func _reinforce(key: String, day: int, p: float) -> void:
	var m := _memory_of(key, day)
	var gap: float = maxf(0.0, float(day) - float(m["last_day"]))
	var growth := 1.0 + ability * (1.5 + 1.5 * (1.0 - p))
	m["stability"] = minf(365.0, float(m["stability"]) * growth + gap * 0.5)
	m["last_day"] = float(day)


## Échec : le fait est réappris grâce au retour immédiat, avec une stabilité réduite.
func _relearn(key: String, day: int) -> void:
	var m := _memory_of(key, day)
	m["stability"] = maxf(0.4 * ability, float(m["stability"]) * 0.5)
	m["last_day"] = float(day)


## Part des faits dont le rappel resterait probable après `horizon` jours sans jeu.
func retention(engine: LearningEngine, day: int, horizon: float) -> float:
	var known := 0
	for key in engine.states:
		var m := _memory_of(key, day)
		var gap: float = float(day) + horizon - float(m["last_day"])
		if exp(-gap / float(m["stability"])) >= 0.8:
			known += 1
	return float(known) / float(engine.states.size())
