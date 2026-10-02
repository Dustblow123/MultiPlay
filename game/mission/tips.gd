class_name Tips
extends RefCounted
## Astuces données par l'équipage (5.2, 6) : régularités de chaque table.
## Affichées seulement sur les faits en apprentissage, jamais pendant une nuée.

const BY_TABLE := {
	1: "×1 : le nombre ne change pas.",
	2: "×2, c'est doubler.",
	3: "×3 : le double, plus une fois le nombre.",
	4: "×4, c'est doubler deux fois.",
	5: "×5 : le résultat finit par 0 ou 5.",
	6: "×6 : le double de ×3.",
	9: "×9 : c'est ×10 moins le nombre ; les chiffres du résultat font 9.",
	10: "×10 : on ajoute un zéro.",
}


static func for_item(item: Dictionary) -> String:
	if item.get("state", "") != "learning" and item.get("mode", "") != "presentation":
		return ""
	var f := Fact.from_key(item["fact"])
	for t in [f.a, f.b]:
		if BY_TABLE.has(t):
			return BY_TABLE[t]
	return ""
