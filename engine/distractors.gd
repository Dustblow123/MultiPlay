class_name Distractors
extends RefCounted
## Génération des distracteurs du QCM (4.8), par ordre de priorité :
## 1. confusions personnelles de l'enfant pour ce fait ;
## 2. voisins dans la table : 7×7 et 7×9 pour 7×8 ;
## 3. voisins de table : 6×8 et 8×8 ;
## 4. inversion de chiffres : 65 pour 56 ;
## 5. un facteur en trop ou en moins : 7×6 et 7×10 (deux pas dans la table).
## Jamais de nombres absurdes qui rendraient la réponse évidente.
##
## Les catégories sont parcourues en tourniquet : un distracteur par catégorie
## dans l'ordre de priorité (les confusions personnelles peuvent en prendre
## deux), puis on complète dans le même ordre.

const MAX_PLAUSIBLE := 120


## Retourne `count` distracteurs distincts, différents de la réponse.
## `confusions` : mauvaises réponses déjà données, triées par fréquence.
static func generate(fact: Fact, count: int, confusions: Array, rng: RandomNumberGenerator) -> Array:
	var answer := fact.product()
	var personal: Array = []
	for c in confusions:
		personal.append(int(c))
	var in_table := [fact.a * (fact.b - 1), fact.a * (fact.b + 1)]
	var table_neighbors := [(fact.a - 1) * fact.b, (fact.a + 1) * fact.b]
	_shuffle(in_table, rng)
	_shuffle(table_neighbors, rng)
	var inversion: Array = []
	if answer >= 10:
		var inverted := _reverse_digits(answer)
		if inverted != answer:
			inversion.append(inverted)
	var far := [fact.a * (fact.b - 2), fact.a * (fact.b + 2), (fact.a - 2) * fact.b, (fact.a + 2) * fact.b]
	_shuffle(far, rng)
	var buckets := [personal, in_table, table_neighbors, inversion, far]
	var quota := [2, 1, 1, 1, 1]

	var result: Array = []
	# Premier passage : une catégorie à la fois, par priorité.
	for i in range(buckets.size()):
		var taken := 0
		for c in buckets[i]:
			if result.size() >= count or taken >= quota[i]:
				break
			if is_plausible(c, answer) and not result.has(c):
				result.append(c)
				taken += 1
	# Second passage : on complète dans l'ordre de priorité.
	for bucket in buckets:
		for c in bucket:
			if result.size() >= count:
				break
			if is_plausible(c, answer) and not result.has(c):
				result.append(c)

	# Secours : autres produits de tables proches de la réponse.
	var attempts := 0
	while result.size() < count and attempts < 200:
		attempts += 1
		var p := rng.randi_range(2, 10) * rng.randi_range(2, 10)
		if is_plausible(p, answer) and not result.has(p) and absi(p - answer) <= maxi(10, answer / 2):
			result.append(p)
	# Dernier recours (faits minuscules) : écarts fixes.
	var offset := 1
	while result.size() < count:
		for c in [answer + offset, answer - offset]:
			if result.size() < count and is_plausible(c, answer) and not result.has(c):
				result.append(c)
		offset += 1
	return result


## Un distracteur est plausible s'il est positif, pas trop grand, différent de la
## réponse et pas absurdement éloigné d'elle.
static func is_plausible(candidate: int, answer: int) -> bool:
	if candidate == answer or candidate <= 0 or candidate > MAX_PLAUSIBLE:
		return false
	# Ne jamais proposer un nombre dont l'ordre de grandeur trahit la réponse.
	if answer >= 10 and candidate < answer / 3:
		return false
	if candidate > answer * 3 + 2:
		return false
	return true


static func _reverse_digits(n: int) -> int:
	var s := str(n)
	var rev := ""
	for i in range(s.length() - 1, -1, -1):
		rev += s[i]
	return int(rev)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
