extends Control
## Retour au hub (2) : récompenses de fin de mission, carte mise à jour ensuite.


func _ready() -> void:
	UI.fill_background(self)
	var r: Dictionary = Game.last_mission_result
	var v := UI.vbox(self, Vector2(40, 30), 6)
	var title := "MISSION ACCOMPLIE" if r.get("completed", false) else "RETRAITE"
	v.add_child(UI.label(title, 28, UI.ACCENT if r.get("completed", false) else UI.MUTED))
	v.add_child(UI.label(UI.mission_name(r.get("type", "")), 14, UI.MUTED))
	v.add_child(UI.label(" ", 6))
	v.add_child(UI.label("Calculs : %d     Justes : %d     Rapides : %d" % [r.get("items", 0), r.get("correct", 0), r.get("fast", 0)], 16))
	v.add_child(UI.label("Meilleur combo : ×%d" % r.get("best_combo", 0), 16))
	var stardust: int = r.get("stardust", 0)
	if r.get("completed", false):
		v.add_child(UI.label("Poussière d'étoile : +%d  ✦" % stardust, 16, UI.ACCENT))
	else:
		v.add_child(UI.label("Bouclier à zéro : la récompense de fin est perdue, mais tout ce que tu as appris est gardé.", 12, UI.MUTED))
	var mastered: Array = r.get("mastered", [])
	if not mastered.is_empty():
		var names: Array = []
		for key in mastered:
			names.append(UI.fact_text(key))
		v.add_child(UI.label("Planètes colonisées : " + ", ".join(names), 14, UI.OK))
	var new_facts: Array = r.get("new_facts", [])
	if not new_facts.is_empty():
		var names2: Array = []
		for key in new_facts:
			names2.append(UI.fact_text(key))
		v.add_child(UI.label("Planètes découvertes : " + ", ".join(names2), 14, UI.TEXT))
	if r.get("boss_beaten", false):
		v.add_child(UI.label("Système ×%d libéré ! Nouvelle pièce de vaisseau et nouveau membre d'équipage." % r.get("boss_table", 0), 14, UI.ACCENT))
	var help := UI.label("A : retour au vaisseau-mère", 12, UI.MUTED)
	help.position = Vector2(40, 330)
	add_child(help)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("canon_A") or event.is_action_pressed("tir") or event.is_action_pressed("canon_B"):
		get_tree().change_scene_to_file("res://game/hub.tscn")
