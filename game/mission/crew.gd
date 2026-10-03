class_name Crew
extends RefCounted
## Équipage (5.3) : un membre rejoint le vaisseau quand son système est libéré
## (boss vaincu). Chaque membre incarne la régularité de sa table et donne
## l'astuce correspondante en mission.

const MEMBERS := {
	1: {"name": "Uno", "role": "le mécano", "tip": "×1 : le nombre ne change pas."},
	10: {"name": "Déci", "role": "la navigatrice", "tip": "×10 : on ajoute un zéro."},
	2: {"name": "Jumo", "role": "le jumeau", "tip": "×2, c'est doubler."},
	5: {"name": "Quinta", "role": "l'astronome", "tip": "×5 : le résultat finit par 0 ou 5."},
	3: {"name": "Trio", "role": "le cuisinier", "tip": "×3 : le double, plus une fois le nombre."},
	4: {"name": "Quadra", "role": "la pilote", "tip": "×4, c'est doubler deux fois."},
	9: {"name": "Mira", "role": "le miroir", "tip": "×9 : c'est ×10 moins le nombre ; les chiffres du résultat font 9."},
	6: {"name": "Sixtine", "role": "la vigie", "tip": "×6 : le double de ×3."},
	7: {"name": "Général Sept", "role": "", "tip": "×7 : la table la plus dure, on la garde en mémoire."},
	8: {"name": "Général Huit", "role": "", "tip": "×8 : c'est doubler trois fois."},
}


static func id_of(table: int) -> String:
	return "crew_%d" % table


static func table_of(id: String) -> int:
	return int(id.trim_prefix("crew_"))


static func name_of(table: int) -> String:
	var m: Dictionary = MEMBERS.get(table, {})
	if m.is_empty():
		return "Gardien ×%d" % table
	return m["name"] + (" " + m["role"] if m["role"] != "" else "")


static func tip_of(table: int) -> String:
	return MEMBERS.get(table, {}).get("tip", "")


## Astuce pour un item (faits en apprentissage ou en présentation seulement),
## attribuée au membre d'équipage quand il a rejoint le vaisseau.
static func tip_for_item(item: Dictionary, unlocked_crew: Array) -> String:
	if item.get("state", "") != "learning" and item.get("mode", "") != "presentation":
		return ""
	var f := Fact.from_key(item["fact"])
	for t in [f.a, f.b]:
		var tip := tip_of(t)
		if tip == "":
			continue
		if unlocked_crew.has(id_of(t)):
			return "%s : « %s »" % [name_of(t), tip]
		return tip
	return ""
