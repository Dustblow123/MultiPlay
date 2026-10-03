extends Node2D
## Mission (3, 6) : le moteur choisit QUOI demander, cette scène choisit COMMENT
## le présenter. Prototype en formes grises : un vaisseau, des ennemis porteurs
## d'un calcul, les 4 canons, la roue de chargement et la décomposition.
##
## Entrée (Input Map, jamais de touches codées en dur) :
##   canon_A/B/X/Y   tirer le nombre chargé dans un canon (QCM) · A : tirer le nombre composé (roue)
##   stick droit     choisir un chiffre sur la roue · tir (RT/Espace/Entrée) : ajouter le chiffre
##   roue_effacer    LT/Retour arrière : effacer le nombre composé
##   deplacer_*      déplacer le vaisseau · pause : Start/Échap

const W := 640
const H := 360
const SHIP_Y := 300.0
const ENEMY_START_Y := 36.0
const ENEMY_HIT_Y := 250.0
const BULLET_TIME_SCALE := 0.35
const FEEDBACK_SEC := 0.7
const PRESENTATION_SEC := 3.0

enum Phase { SPAWN, ACTIVE, FEEDBACK, DONE }

var context: Dictionary
var items_total: int = Game.MISSION_ITEMS
var item_index: int = 0
var shield: int = Game.SHIELD_MAX
var combo: int = 0
var best_combo: int = 0
var stardust: int = 0
var correct_count: int = 0
var fast_count: int = 0
var mastered_keys: Array = []
var new_keys: Array = []

var item: Dictionary = {}
var phase: int = Phase.SPAWN
var _item_start_ms: int = 0
var _reported: bool = false
var _enemy_speed: float = 0.0
var _feedback_left: float = 0.0
var _presses: Array = []
var _composed: String = ""
var _wheel_digit: int = -1
var _decomp_remaining: int = -1
var _wrong_this_item: bool = false
var _boss_phase: int = 0
var _paused_label: Label

# Nœuds
var _ship: Node2D
var _enemy: Node2D
var _enemy_label: Label
var _enemy_body: Sprite2D
var _cannons: Array = []
var _cannon_labels: Array = []
var _wheel: Node2D
var _wheel_digits: Array = []
var _composed_label: Label
var _hud: Label
var _message: Label
var _subtitle: Label
var _shield_rect: Array = []
var _tip_label: Label
var _rng := RandomNumberGenerator.new()
var _stars: Array = []
var _particles: Array = []
var _shield_blink_left: float = 0.0
var _hull: Sprite2D
var _trail_left: float = 0.0
## Arène (6) : score, combos, records personnels.
var score: int = 0
var is_arena: bool = false
var is_boss: bool = false
var _boss_bar: ColorRect
var _boss_label: Label
var is_defense: bool = false
var is_duel: bool = false
var _planet_label: Label
## Calcul inversé (3) : le vaisseau porte le calcul, une nuée porte les nombres,
## on se place sous le bon et on tire. Variante de vague des items QCM.
var _inverted: bool = false
var _swarm: Array = []
var _swarm_labels: Array = []
var _swarm_values: Array = []
var _target: Node2D
var _ship_label: Label
const SWARM_HIT_HALF_WIDTH := 34.0
const INVERTED_CHANCE := 0.4
## Nuée rapide (4.3) : plusieurs faits maîtrisés à la fois, réponse à la roue,
## tir sur l'ennemi aligné. Chaque entrée : {item, node, label, reported, wrong, start_ms, done}.
var _wave: Array = []
const WAVE_SIZE := 3
const WAVE_CHANCE := 0.5
const WAVE_MIN_MASTERED := 4
var _planet_shield: Array = []
var _last_outcome: Dictionary = {}
var _intro_shown: bool = false


func _ready() -> void:
	context = Game.mission_context.duplicate(true)
	Game.ensure_session()
	_rng.randomize()
	for _i in range(90):
		_stars.append(Vector3(_rng.randf() * W, _rng.randf() * H, _rng.randf_range(0.3, 1.0)))
	_build_scene()
	is_arena = context.get("type", "") == LearningEngine.MISSION_ARENA
	is_boss = context.get("boss", false)
	is_defense = context.get("type", "") == LearningEngine.MISSION_DEFENSE
	is_duel = context.get("type", "") == LearningEngine.MISSION_DUEL
	if is_defense:
		_build_planet_panel()
	if is_boss:
		items_total = 15
		_build_boss_bar()
	if is_arena:
		items_total = 25
	Game.controller_disconnected.connect(_on_controller_disconnected)
	Game.controller_reconnected.connect(_on_controller_reconnected)
	_next_item()


func _build_scene() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.size = Vector2(W, H)
	add_child(bg)

	_ship = Node2D.new()
	_ship.position = Vector2(W / 2.0, SHIP_Y)
	_hull = ShipView.build(_ship, Game.profile)
	add_child(_ship)

	_enemy = Node2D.new()
	_enemy_body = PixelArt.sprite("enemy", {}, 3.0)
	_enemy.add_child(_enemy_body)
	_enemy_label = UI.big_number("", 26)
	_enemy_label.position = Vector2(-60, -2)
	_enemy_label.size = Vector2(120, 36)
	_enemy.add_child(_enemy_label)
	_enemy.visible = false
	add_child(_enemy)

	for i in range(4):
		var e := Node2D.new()
		var body := PixelArt.sprite("enemy", {}, 3.0)
		e.add_child(body)
		var l := UI.big_number("", 24)
		l.position = Vector2(-50, -2)
		l.size = Vector2(100, 32)
		e.add_child(l)
		e.visible = false
		add_child(e)
		_swarm.append(e)
		_swarm_labels.append(l)
	_ship_label = UI.big_number("", 22, UI.ACCENT)
	_ship_label.position = Vector2(-60, -60)
	_ship_label.size = Vector2(120, 30)
	_ship_label.visible = false
	_ship.add_child(_ship_label)

	# Les 4 canons, couleurs Xbox avec la lettre affichée (8).
	var x0 := W / 2.0 - 190
	for i in range(4):
		var letter: String = UI.BUTTON_ORDER[i]
		var cannon := Node2D.new()
		cannon.position = Vector2(x0 + i * 120, 328)
		var box := UI.rect(Color(0.15, 0.17, 0.25), Vector2(100, 30))
		box.position = Vector2(-50, -15)
		cannon.add_child(box)
		var badge := UI.rect(UI.BUTTON_COLORS[letter], Vector2(22, 22))
		badge.position = Vector2(-46, -11)
		cannon.add_child(badge)
		var bl := UI.label(letter, 14, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
		bl.add_theme_constant_override("outline_size", 0)
		bl.size = Vector2(22, 22)
		bl.position = Vector2(-46, -10)
		cannon.add_child(bl)
		var num := UI.big_number("", 22)
		num.position = Vector2(-20, -15)
		num.size = Vector2(68, 30)
		cannon.add_child(num)
		cannon.visible = false
		add_child(cannon)
		_cannons.append(cannon)
		_cannon_labels.append(num)

	# Roue de chargement : 10 chiffres en anneau, choisis au stick droit.
	_wheel = Node2D.new()
	_wheel.position = Vector2(W - 70, 270)
	for d in range(10):
		var angle := -PI / 2 + d * TAU / 10.0
		var l := UI.big_number(str(d), 16, UI.MUTED)
		l.position = Vector2(cos(angle) * 44 - 10, sin(angle) * 44 - 10)
		l.size = Vector2(20, 20)
		_wheel.add_child(l)
		_wheel_digits.append(l)
	_composed_label = UI.big_number("", 26, UI.ACCENT)
	_composed_label.position = Vector2(-40, -14)
	_composed_label.size = Vector2(80, 28)
	_wheel.add_child(_composed_label)
	var wheel_help := UI.label("RT : ajouter  A : tirer  LT : effacer", 9, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	wheel_help.position = Vector2(-70, 56)
	wheel_help.size = Vector2(140, 14)
	_wheel.add_child(wheel_help)
	_wheel.visible = false
	add_child(_wheel)

	_hud = UI.label("", 13, UI.TEXT)
	_hud.position = Vector2(10, 6)
	add_child(_hud)
	for i in range(Game.SHIELD_MAX):
		var r := UI.rect(UI.OK, Vector2(16, 8))
		r.position = Vector2(W - 70 + i * 20, 10)
		add_child(r)
		_shield_rect.append(r)
	var shield_label := UI.label("Bouclier", 10, UI.MUTED)
	shield_label.position = Vector2(W - 70, 20)
	add_child(shield_label)

	_message = UI.big_number("", 20, UI.ACCENT)
	_message.position = Vector2(W / 2.0 - 200, 150)
	_message.size = Vector2(400, 30)
	add_child(_message)
	_subtitle = UI.label("", 12, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.position = Vector2(W / 2.0 - 200, 182)
	_subtitle.size = Vector2(400, 20)
	add_child(_subtitle)
	_tip_label = UI.label("", 11, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_tip_label.position = Vector2(W / 2.0 - 220, 70)
	_tip_label.size = Vector2(440, 20)
	add_child(_tip_label)

	_paused_label = UI.big_number("PAUSE", 32)
	_paused_label.position = Vector2(W / 2.0 - 100, 120)
	_paused_label.size = Vector2(200, 40)
	_paused_label.visible = false
	_paused_label.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_paused_label)
	_update_hud()


func _draw() -> void:
	for s in _stars:
		draw_rect(Rect2(s.x, s.y, 2, 2), Color(UI.STAR, 0.25 + 0.4 * s.z))


# ---------------------------------------------------------------------------
# Déroulé
# ---------------------------------------------------------------------------

func _item_context() -> Dictionary:
	var ctx := context.duplicate(true)
	if ctx.get("boss", false):
		# Trois phases (7) : points faibles (roue), décomposition, rafale finale.
		var third := items_total / 3
		_boss_phase = mini(2, item_index / maxi(1, third))
		if _boss_phase == 1:
			ctx["mode_hint"] = LearningEngine.MODE_DECOMPOSITION
	return ctx


func _next_item() -> void:
	if item_index >= items_total or shield <= 0:
		_finish()
		return
	item = Game.engine.next_item(_item_context())
	item_index += 1
	_reported = false
	_wrong_this_item = false
	_presses.clear()
	_composed = ""
	_decomp_remaining = -1
	_message.text = ""
	_subtitle.text = ""
	_tip_label.text = Crew.tip_for_item(item, Game.profile.unlocks["crew"])
	_enemy.position = Vector2(_rng.randf_range(120, W - 120), ENEMY_START_Y)
	_enemy.scale = Vector2.ONE
	_set_enemy_look("enemy")
	_enemy.visible = true
	_enemy_label.text = item["question"]
	_last_outcome = {}
	_inverted = false
	_wave = []
	_target = null
	_ship_label.visible = false
	for e in _swarm:
		e.visible = false
	if is_defense:
		_update_planet_panel()
	if is_duel:
		# Le Confondeur (6) : ennemi spécial, violet, qui alterne les deux calculs confondus.
		_set_enemy_look("confondeur")
		if not _intro_shown and context.has("pair"):
			_intro_shown = true
			_message.text = "LE CONFONDEUR"
			_subtitle.text = "Il mélange %s et %s : ne te laisse pas avoir !" % [UI.fact_text(context["pair"][0]), UI.fact_text(context["pair"][1])]
			Sfx.play("boss", 1.5)
	for c in _cannons:
		c.visible = false
	_wheel.visible = false

	match item["mode"]:
		LearningEngine.MODE_PRESENTATION:
			# Première rencontre en « scan » : calcul + réponse affichés (6).
			Sfx.play("scan")
			_enemy_label.text = "%s = %d" % [item["question"], item["answer"]]
			_set_enemy_look("enemy", Color(0.6, 0.8, 1.2))
			_message.text = "SCAN : nouvelle planète"
			_subtitle.text = "Mémorise, puis appuie sur un bouton"
			_enemy_speed = 0.0
		LearningEngine.MODE_QCM:
			_inverted = int(item.get("box", 0)) >= 2 and not is_duel and _rng.randf() < INVERTED_CHANCE
			if _inverted:
				_start_inverted_wave()
			else:
				for i in range(4):
					_cannons[i].visible = true
					_cannon_labels[i].text = str(item["options"][i])
			_enemy_speed = _speed_for(item, 2.6 if not _inverted else 3.2)
		LearningEngine.MODE_WHEEL:
			_wheel.visible = true
			_enemy_speed = _speed_for(item, 2.2 if item["state"] == "mastered" else 3.0)
			if is_arena:
				_enemy_speed *= 1.3
			if item["state"] == "mastered" and not is_duel and not is_boss \
					and Game.engine.counts_by_state()["mastered"] >= WAVE_MIN_MASTERED \
					and (is_arena or _rng.randf() < WAVE_CHANCE):
				_start_wave()
		LearningEngine.MODE_DECOMPOSITION:
			_wheel.visible = true
			_subtitle.text = "Décompose : tire un facteur"
			_enemy_speed = _speed_for(item, 3.0)
	if context.get("boss", false) and _boss_phase == 2:
		_enemy_speed *= 1.6
	if is_boss and item_index == 1:
		Sfx.play("boss")
	if is_boss:
		_update_boss_bar()
	_update_composed()
	_item_start_ms = Time.get_ticks_msec()
	phase = Phase.ACTIVE
	_update_hud()


## Vitesse de descente fixée par le temps cible du moteur (3) : l'ennemi atteint
## le vaisseau après `factor` fois le temps cible.
func _speed_for(it: Dictionary, factor: float) -> float:
	var seconds: float = maxf(1.0, float(it["target_time_ms"]) / 1000.0 * factor)
	return (ENEMY_HIT_Y - ENEMY_START_Y) / seconds


func _process(delta: float) -> void:
	_poll_input()
	_update_particles(delta)
	_update_shield_blink(delta)
	if phase == Phase.ACTIVE:
		_move_ship(delta)
		_enemy.position.y += _enemy_speed * delta
		for e in _swarm:
			e.position.y += _enemy_speed * delta
		if item["mode"] == LearningEngine.MODE_PRESENTATION:
			if Time.get_ticks_msec() - _item_start_ms >= PRESENTATION_SEC * 1000:
				_acknowledge_presentation()
		elif _front_y() >= ENEMY_HIT_Y:
			_enemy_reached_ship()
		_update_wheel_selection()
	elif phase == Phase.FEEDBACK:
		_feedback_left -= delta
		if _feedback_left <= 0.0:
			_next_item()


func _move_ship(delta: float) -> void:
	var axis := Input.get_action_strength("deplacer_droite") - Input.get_action_strength("deplacer_gauche")
	_ship.position.x = clampf(_ship.position.x + axis * 220.0 * delta, 24, W - 24)
	_emit_trail(delta)


## Traînée cosmétique (5.3) derrière le vaisseau.
func _emit_trail(delta: float) -> void:
	var trail := Cosmetics.trail(Game.profile)
	if trail == "none":
		return
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = 0.06
	var color := UI.ACCENT if trail == "stars" else Color("fb923c")
	var r := UI.rect(color, Vector2(3, 3))
	r.position = _ship.position + Vector2(_rng.randf_range(-5, 5), 12)
	add_child(r)
	_particles.append({"node": r, "vel": Vector2(_rng.randf_range(-15, 15), 60), "life": 0.4})


## Défense (5.4, 6) : la planète attaquée est visible en bas, avec son bouclier.
func _build_planet_panel() -> void:
	var panel := UI.rect(Color(0.12, 0.14, 0.22), Vector2(200, 34))
	panel.position = Vector2(8, 40)
	add_child(panel)
	_planet_label = UI.label("", 11, UI.TEXT)
	_planet_label.position = Vector2(14, 42)
	add_child(_planet_label)
	for i in range(Game.SHIELD_MAX):
		var r := UI.rect(Color("60a5fa"), Vector2(40, 5))
		r.position = Vector2(14 + i * 44, 64)
		add_child(r)
		_planet_shield.append(r)


func _update_planet_panel() -> void:
	if _planet_label == null:
		return
	var fs: FactState = Game.engine.fact_state(item["fact"])
	var status: String = {"dark": "inconnue", "orbit": "en orbite", "colonized": "colonisée", "besieged": "assiégée"}[Game.engine.planet_status(fs)]
	if item.get("is_due", false):
		_planet_label.text = "Pirates sur la planète %s (%s) !" % [UI.fact_text(item["fact"]), status]
		_set_enemy_look("pirate")
	else:
		_planet_label.text = "Patrouille : planète %s (%s)" % [UI.fact_text(item["fact"]), status]
	for i in range(_planet_shield.size()):
		_planet_shield[i].color = Color("60a5fa") if i < shield else Color(0.25, 0.25, 0.3)


func _set_enemy_look(kind: String, tint: Color = Color.WHITE) -> void:
	_enemy_body.texture = PixelArt.texture(kind)
	_enemy_body.modulate = tint
	# Le calcul reste au premier plan, sous le vaisseau ennemi.
	_enemy_label.position = Vector2(-60, 4 if kind == "boss" else -2)


func outcome_fast_hint(text: String) -> bool:
	return text == "Rapide !" or text == "PLANÈTE COLONISÉE !"


## Boss (7) : barre de résistance fixée par le nombre de faits, et nom de la phase.
func _build_boss_bar() -> void:
	var back := UI.rect(Color(0.2, 0.2, 0.25), Vector2(300, 8))
	back.position = Vector2(W / 2.0 - 150, 30)
	add_child(back)
	_boss_bar = UI.rect(UI.BAD, Vector2(300, 8))
	_boss_bar.position = Vector2(W / 2.0 - 150, 30)
	add_child(_boss_bar)
	_boss_label = UI.label("", 11, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_label.position = Vector2(W / 2.0 - 150, 40)
	_boss_label.size = Vector2(300, 16)
	add_child(_boss_label)


func _update_boss_bar() -> void:
	if _boss_bar == null:
		return
	_boss_bar.size.x = 300.0 * (1.0 - float(item_index - 1) / float(items_total))
	var table: int = context["tables"][0]
	var phases := ["Phase 1 : points faibles", "Phase 2 : décomposition", "Phase 3 : rafale finale"]
	_boss_label.text = "%s  ·  %s" % [Hub.boss_name_of(table).split(" :")[0], phases[_boss_phase]]
	_set_enemy_look("boss")
	_enemy.scale = Vector2(1.2, 1.2) if _boss_phase < 2 else Vector2(0.9, 0.9)


func _unhandled_input(event: InputEvent) -> void:
	# Seules les touches chiffrées du clavier passent par les événements ; le
	# reste est sondé dans _poll_input (les gâchettes sont des axes, qui
	# génèrent plusieurs événements par appui).
	if phase != Phase.ACTIVE or get_tree().paused or not _wheel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode >= KEY_0 and k.keycode <= KEY_9:
			wheel_add_digit(k.keycode - KEY_0)
		elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
			wheel_add_digit(k.keycode - KEY_KP_0)


func _poll_input() -> void:
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
		return
	if phase != Phase.ACTIVE or get_tree().paused:
		return
	match item["mode"]:
		LearningEngine.MODE_PRESENTATION:
			for letter in UI.BUTTON_ORDER:
				if Input.is_action_just_pressed(UI.BUTTON_ACTIONS[letter]):
					_acknowledge_presentation()
					return
			if Input.is_action_just_pressed("tir"):
				_acknowledge_presentation()
		LearningEngine.MODE_QCM:
			if _inverted:
				if Input.is_action_just_pressed("tir") or Input.is_action_just_pressed("canon_A"):
					fire_inverted()
				return
			for i in range(4):
				if Input.is_action_just_pressed(UI.BUTTON_ACTIONS[UI.BUTTON_ORDER[i]]):
					press_cannon(i)
					return
		_:
			if Input.is_action_just_pressed("tir"):
				wheel_add_selected_digit()
			elif Input.is_action_just_pressed("canon_A"):
				wheel_fire()
			elif Input.is_action_just_pressed("roue_effacer"):
				wheel_clear()


func _toggle_pause() -> void:
	if Game.paused_for_controller:
		return
	get_tree().paused = not get_tree().paused
	_paused_label.visible = get_tree().paused
	_paused_label.text = "PAUSE"


func _on_controller_disconnected() -> void:
	_paused_label.text = "MANETTE DÉBRANCHÉE"
	_paused_label.visible = true


func _on_controller_reconnected() -> void:
	_paused_label.visible = false


# ---------------------------------------------------------------------------
# Réponses
# ---------------------------------------------------------------------------

func _elapsed_ms() -> int:
	return Time.get_ticks_msec() - _item_start_ms


func _acknowledge_presentation() -> void:
	if _reported:
		return
	_report(item["answer"], {})
	combo = 0
	_resolve(true, "Planète scannée", false)


## QCM (3) : on tire avec le canon chargé du bon nombre.
func press_cannon(index: int) -> void:
	if phase != Phase.ACTIVE or item["mode"] != LearningEngine.MODE_QCM:
		return
	var now := Time.get_ticks_msec()
	_presses.append(now)
	var recent := 0
	for t in _presses:
		if now - t <= 1000:
			recent += 1
	var answer: int = item["options"][index]
	Sfx.play("shoot")
	_spawn_tracer(_ship.position + Vector2(0, -16), _enemy.position, UI.BUTTON_COLORS[UI.BUTTON_ORDER[index]])
	_submit(answer, {"mashing": recent >= 3})


## Vague inversée : le calcul passe sur le vaisseau, les 4 nombres sur une nuée.
func _start_inverted_wave() -> void:
	_enemy.visible = false
	_ship_label.text = item["question"]
	_ship_label.visible = true
	_subtitle.text = "Place-toi sous le bon nombre et tire"
	var slots := [0, 1, 2, 3]
	_shuffle_slots(slots)
	_swarm_values = []
	for i in range(4):
		var e: Node2D = _swarm[i]
		var x: float = 100.0 + float(slots[i]) * (W - 200.0) / 3.0 + _rng.randf_range(-12, 12)
		e.position = Vector2(x, ENEMY_START_Y + _rng.randf_range(0, 10))
		e.scale = Vector2.ONE
		e.get_child(0).modulate = Color.WHITE
		e.visible = true
		var value: int = item["options"][i]
		_swarm_labels[i].text = str(value)
		_swarm_values.append(value)


func _shuffle_slots(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Tir vertical depuis le vaisseau : touche l'ennemi aligné, sinon rate (sans pénalité).
func fire_inverted() -> void:
	if phase != Phase.ACTIVE or not _inverted:
		return
	Sfx.play("shoot")
	var best: Node2D = null
	var best_dx := SWARM_HIT_HALF_WIDTH
	for e in _swarm:
		if not e.visible:
			continue
		var dx: float = absf(e.position.x - _ship.position.x)
		if dx <= best_dx:
			best_dx = dx
			best = e
	var top := Vector2(_ship.position.x, best.position.y if best != null else 0.0)
	_spawn_tracer(_ship.position + Vector2(0, -16), top, UI.ACCENT)
	if best == null:
		_message.text = "Raté !"
		return
	_target = best
	var answer: int = _swarm_values[_swarm.find(best)]
	_submit(answer, {"variant": "inverted"})


## Nuée rapide : l'item courant plus d'autres faits maîtrisés demandés au moteur.
func _start_wave() -> void:
	_enemy.visible = false
	var items: Array = [item]
	var extra := mini(WAVE_SIZE, items_total - item_index + 1) - 1
	for _i in range(extra):
		var it := Game.engine.next_item({"type": LearningEngine.MISSION_ARENA})
		if it["mode"] != LearningEngine.MODE_WHEEL:
			# Pas assez de faits maîtrisés disponibles : on reste sur l'item seul.
			Game.engine.report_result(it, -1, 0)
			break
		items.append(it)
		item_index += 1
	if items.size() == 1:
		_enemy.visible = true
		return
	var slots := range(items.size())
	_shuffle_slots(slots)
	_wave = []
	var now := Time.get_ticks_msec()
	for i in range(items.size()):
		var e: Node2D = _swarm[i]
		var x: float = 110.0 + float(slots[i]) * (W - 220.0) / float(items.size() - 1)
		e.position = Vector2(x, ENEMY_START_Y + _rng.randf_range(0, 12))
		e.scale = Vector2.ONE
		e.get_child(0).modulate = Color.WHITE
		e.visible = true
		_swarm_labels[i].text = items[i]["question"]
		_wave.append({"item": items[i], "node": e, "label": _swarm_labels[i], "reported": false, "wrong": false, "start_ms": now, "done": false})
	_subtitle.text = "Nuée ! Compose, place-toi sous l'ennemi visé et tire"
	Sfx.play("combo", 1.3)


## Tir d'un nombre composé sur l'ennemi aligné de la nuée.
func fire_wave(value: int) -> void:
	var entry: Dictionary = {}
	var best_dx := SWARM_HIT_HALF_WIDTH
	for w in _wave:
		if w["done"]:
			continue
		var dx: float = absf(w["node"].position.x - _ship.position.x)
		if dx <= best_dx:
			best_dx = dx
			entry = w
	var top := Vector2(_ship.position.x, entry["node"].position.y if not entry.is_empty() else 0.0)
	_spawn_tracer(_ship.position + Vector2(0, -16), top, UI.ACCENT)
	if entry.is_empty():
		_message.text = "Raté !"
		return
	var it: Dictionary = entry["item"]
	var correct: bool = it["accepted"].has(value)
	var outcome := {}
	if not entry["reported"]:
		entry["reported"] = true
		outcome = _report_item(it, entry["start_ms"], value, {"variant": "wave"})
	_target = entry["node"]
	if correct:
		entry["done"] = true
		entry["node"].visible = false
		_spawn_explosion(entry["node"].position, UI.ACCENT if outcome.get("stardust", 0) > 0 else UI.GREY)
		if outcome.get("stardust", 0) > 0:
			combo += 1
			best_combo = maxi(best_combo, combo)
			stardust += 1
			Game.profile.stardust += 1
			Game.vibrate()
			_hull.modulate = Color.WHITE.lerp(Color(1.6, 1.6, 1.2), minf(combo, 6) / 6.0)
			if is_arena:
				score += 10 * mini(combo, 10) + (5 if outcome.get("fast", false) else 0)
			Sfx.play("fast" if outcome.get("fast", false) else "good", 1.0 + 0.03 * minf(combo, 10))
			_message.text = "Rapide !" if outcome.get("fast", false) else "Juste !"
		if _wave_done():
			_resolve_wave()
	else:
		entry["wrong"] = true
		_wrong_hit(value, true)
		_subtitle.text = "Réponse : %d" % it["answer"] if shield <= 0 else "Essaie encore : %s" % it["question"]


func _wave_done() -> bool:
	for w in _wave:
		if not w["done"]:
			return false
	return true


func _resolve_wave() -> void:
	phase = Phase.FEEDBACK
	_feedback_left = FEEDBACK_SEC
	Engine.time_scale = 1.0
	_message.text = "Nuée repoussée !" if shield > 0 else "Bouclier à zéro : retraite"
	if combo >= 3:
		_subtitle.text = "Combo ×%d" % combo
	for w in _wave:
		w["node"].visible = false
	_wheel.visible = false
	_update_hud()


## La nuée atteint le vaisseau : les calculs restants sont manqués, un seul point de bouclier.
func _wave_reached_ship() -> void:
	var missed: Array = []
	for w in _wave:
		if w["done"]:
			continue
		if not w["reported"]:
			w["reported"] = true
			_report_item(w["item"], w["start_ms"], -1, {"variant": "wave"})
		missed.append("%s = %d" % [w["item"]["question"], w["item"]["answer"]])
		w["done"] = true
	combo = 0
	shield -= 1
	_shield_blink_left = 0.6
	_hull.modulate = Color.WHITE
	Sfx.play("hit")
	_update_hud()
	phase = Phase.FEEDBACK
	_feedback_left = FEEDBACK_SEC + 0.6
	Engine.time_scale = 1.0
	_message.text = "La nuée est passée"
	_subtitle.text = "  ·  ".join(missed)
	for w in _wave:
		w["node"].visible = false
	_wheel.visible = false


## Position de ce qui vient d'être touché (explosion) et avant de la vague.
func _target_position() -> Vector2:
	return _target.position if _target != null else _enemy.position


func _front_y() -> float:
	if not _inverted and _wave.is_empty():
		return _enemy.position.y
	var y := 0.0
	for e in _swarm:
		if e.visible:
			y = maxf(y, e.position.y)
	return y


## Traceur de tir : une ligne de points du vaisseau vers la cible, visuel seulement.
func _spawn_tracer(from: Vector2, to: Vector2, color: Color) -> void:
	var steps := 6
	for i in range(steps):
		var r := UI.rect(color, Vector2(3, 6))
		r.position = from.lerp(to, float(i) / steps)
		add_child(r)
		_particles.append({"node": r, "vel": (to - from).normalized() * 500.0, "life": 0.12 + i * 0.03})


## Roue (3) : on compose la réponse chiffre par chiffre, puis on tire.
func wheel_add_digit(d: int) -> void:
	if phase != Phase.ACTIVE or _composed.length() >= 3:
		return
	_composed += str(d)
	_update_composed()


func wheel_add_selected_digit() -> void:
	if _wheel_digit >= 0:
		wheel_add_digit(_wheel_digit)


func wheel_clear() -> void:
	_composed = ""
	_update_composed()


func wheel_fire() -> void:
	if phase != Phase.ACTIVE or _composed.is_empty():
		return
	var value := int(_composed)
	_composed = ""
	_update_composed()
	Sfx.play("shoot")
	if not _wave.is_empty():
		fire_wave(value)
		return
	_submit(value, {})


func _submit(answer: int, flags: Dictionary) -> void:
	if item["mode"] == LearningEngine.MODE_DECOMPOSITION and _decomp_remaining >= 0:
		# Seconde étape : achever le facteur restant (vérifié localement).
		if answer == _decomp_remaining:
			_resolve(true, "Décomposé !", false)
		else:
			_wrong_hit(answer, false)
		return
	var accepted: Array = item["accepted"]
	var correct := accepted.has(answer)
	var outcome := {}
	if not _reported:
		outcome = _report(answer, flags)
	if correct:
		if item["mode"] == LearningEngine.MODE_DECOMPOSITION:
			_decomp_remaining = int(item["answer"]) if answer != int(item["answer"]) else int(item["accepted"][-1])
			if item["accepted"].size() == 1:
				_decomp_remaining = answer
			_enemy_label.text = str(_decomp_remaining)
			_subtitle.text = "Reste %d : achève-le !" % _decomp_remaining
			_enemy.scale = Vector2(0.8, 0.8)
			return
		_resolve(true, _success_text(outcome), outcome.get("stardust", 0) > 0)
	else:
		_wrong_hit(answer, true)


func _report(answer: int, flags: Dictionary) -> Dictionary:
	_reported = true
	return _report_item(item, _item_start_ms, answer, flags)


func _report_item(it: Dictionary, start_ms: int, answer: int, flags: Dictionary) -> Dictionary:
	var outcome := Game.engine.report_result(it, answer, Time.get_ticks_msec() - start_ms, flags)
	_last_outcome = outcome
	if outcome["mastered_now"]:
		mastered_keys.append(it["fact"])
	if it["mode"] == LearningEngine.MODE_PRESENTATION:
		new_keys.append(it["fact"])
	elif outcome["correct"] and not outcome["suspicious"]:
		correct_count += 1
		if outcome["fast"]:
			fast_count += 1
	Game.touch()
	return outcome


func _success_text(outcome: Dictionary) -> String:
	if outcome.get("mastered_now", false):
		return "PLANÈTE COLONISÉE !"
	if outcome.get("suspicious", false):
		return "Trop vite pour compter…"
	if outcome.get("fast", false):
		return "Rapide !"
	return "Juste !"


## Toucher un mauvais nombre ne tue pas (3) : l'ennemi est renforcé, le bouclier
## diminue, le calcul reste à l'écran jusqu'à la bonne réponse.
func _wrong_hit(_answer: int, first: bool) -> void:
	combo = 0
	shield -= 1
	_wrong_this_item = true
	_shield_blink_left = 0.6
	_hull.modulate = Color.WHITE
	Sfx.play("error")
	if _inverted and _target != null:
		_target.scale = _target.scale * 1.15
		_target.get_child(0).modulate = Color(1.3, 0.6, 0.6)
	else:
		_enemy.scale = _enemy.scale * 1.15
		_enemy_body.modulate = Color(1.3, 0.6, 0.6)
	_message.text = "Ennemi renforcé"
	var expected: int = _decomp_remaining if _decomp_remaining >= 0 else int(item["answer"])
	_subtitle.text = "Réponse : %d" % expected if (shield <= 0 or not first) else "Essaie encore"
	_update_hud()
	if shield <= 0:
		_resolve(false, "Bouclier à zéro : retraite", false)


func _enemy_reached_ship() -> void:
	if not _wave.is_empty():
		_wave_reached_ship()
		return
	if not _reported:
		_report(-1, {})
	combo = 0
	# Un même ennemi ne coûte qu'un point de bouclier, même s'il a déjà été manqué.
	if not _wrong_this_item:
		shield -= 1
		_shield_blink_left = 0.6
	_hull.modulate = Color.WHITE
	Sfx.play("hit")
	_update_hud()
	_resolve(false, "La planète est assiégée (réponse : %d)" % item["answer"], false)


func _resolve(success: bool, text: String, reward: bool) -> void:
	phase = Phase.FEEDBACK
	_feedback_left = FEEDBACK_SEC
	Engine.time_scale = 1.0
	_message.text = text
	if success and item["mode"] != LearningEngine.MODE_PRESENTATION:
		# Explosion satisfaisante, son net et positif, courte vibration (8).
		_spawn_explosion(_target_position(), UI.ACCENT if reward else UI.GREY)
		if reward:
			combo += 1
			best_combo = maxi(best_combo, combo)
			stardust += 1
			Game.profile.stardust += 1
			Game.vibrate()
			# Série de réussites : le vaisseau s'illumine, la musique s'intensifie.
			_hull.modulate = Color.WHITE.lerp(Color(1.6, 1.6, 1.2), minf(combo, 6) / 6.0)
			if is_arena:
				# Score d'arène : 10 points × combo (plafonné à 10), bonus de rapidité.
				score += 10 * mini(combo, 10) + (5 if outcome_fast_hint(text) else 0)
			if text == "PLANÈTE COLONISÉE !":
				Sfx.play("colonize")
			elif combo > 0 and combo % 5 == 0:
				Sfx.play("combo", 1.0 + 0.05 * (combo / 5))
			else:
				Sfx.play("fast" if _reported and fast_count > 0 and text == "Rapide !" else "good", 1.0 + 0.03 * minf(combo, 10))
			if combo >= 3:
				_subtitle.text = "Combo ×%d" % combo
			if is_defense and item.get("is_due", false):
				# Planète sauvée, intervalle allongé (6) quand la boîte a monté.
				var advanced: bool = int(_last_outcome.get("box", 0)) > int(item.get("box", 0))
				_subtitle.text = "Planète %s sauvée%s" % [UI.fact_text(item["fact"]), " : intervalle allongé !" if advanced else ""]
	_enemy.visible = false
	for e in _swarm:
		e.visible = false
	_ship_label.visible = false
	for c in _cannons:
		c.visible = false
	_wheel.visible = false
	_update_hud()


func _finish() -> void:
	phase = Phase.DONE
	Engine.time_scale = 1.0
	var completed := shield > 0
	var result := {
		"type": context.get("type", ""),
		"completed": completed,
		"items": item_index,
		"correct": correct_count,
		"fast": fast_count,
		"best_combo": best_combo,
		"stardust": stardust if completed else 0,
		"mastered": mastered_keys,
		"new_facts": new_keys,
	}
	if is_arena:
		result["score"] = score
		var record: int = Game.profile.records.get("arena_score", 0)
		result["new_record"] = completed and score > record
		if result["new_record"]:
			Game.profile.records["arena_score"] = score
	if not completed:
		# Échec doux (6) : les réponses sont gardées, seule la récompense de fin est perdue.
		Game.profile.stardust -= stardust
	if context.get("boss", false) and completed:
		var table: int = context["tables"][0]
		Game.profile.unlocks["ship_parts"].append("boss_%d" % table)
		Game.profile.unlocks["crew"].append("crew_%d" % table)
		result["boss_beaten"] = true
		result["boss_table"] = table
		result["crew_name"] = Crew.name_of(table)
	Game.last_mission_result = result
	Game.save()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://game/ui/results.tscn")


# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	if is_arena:
		_hud.text = "Arène   %d/%d   Score %d   Combo ×%d   Record %d" % [item_index, items_total, score, combo, Game.profile.records.get("arena_score", 0)]
	else:
		_hud.text = "%s   %d/%d   Combo ×%d   ✦ %d" % [UI.mission_name(context.get("type", "")), item_index, items_total, combo, stardust]
	for i in range(_shield_rect.size()):
		_shield_rect[i].color = UI.OK if i < shield else Color(0.25, 0.25, 0.3)
	for i in range(_planet_shield.size()):
		_planet_shield[i].color = Color("60a5fa") if i < shield else Color(0.25, 0.25, 0.3)


func _update_composed() -> void:
	_composed_label.text = _composed if not _composed.is_empty() else "_"


## Stick droit : angle -> chiffre, avec zone morte réglable (3, 9). Pendant la
## composition, un ralenti (« bullet time ») laisse le temps de réfléchir.
func _update_wheel_selection() -> void:
	if not _wheel.visible:
		Engine.time_scale = 1.0
		return
	var composing := not _composed.is_empty()
	if Game.has_controller():
		var device: int = Input.get_connected_joypads()[0]
		var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if v.length() >= Game.deadzone():
			var angle := fposmod(v.angle() + PI / 2, TAU)
			_wheel_digit = int(round(angle / (TAU / 10.0))) % 10
			composing = true
		else:
			_wheel_digit = -1
	for d in range(10):
		_wheel_digits[d].add_theme_color_override("font_color", UI.ACCENT if d == _wheel_digit else UI.MUTED)
	Engine.time_scale = BULLET_TIME_SCALE if composing else 1.0


## Explosion en formes grises : des éclats qui s'écartent puis s'éteignent.
## Aucun effet ne masque le calcul suivant : les éclats vivent 0,4 s.
func _spawn_explosion(pos: Vector2, color: Color) -> void:
	for _i in range(14):
		var r := UI.rect(color, Vector2(4, 4))
		r.position = pos
		add_child(r)
		var angle := _rng.randf() * TAU
		var speed := _rng.randf_range(80, 220)
		_particles.append({"node": r, "vel": Vector2(cos(angle), sin(angle)) * speed, "life": 0.4})


func _update_particles(delta: float) -> void:
	var alive: Array = []
	for p in _particles:
		p["life"] -= delta
		var node: ColorRect = p["node"]
		if p["life"] <= 0.0:
			node.queue_free()
			continue
		node.position += p["vel"] * delta
		node.modulate.a = p["life"] / 0.4
		alive.append(p)
	_particles = alive


## Erreur : le bouclier clignote (8), sans vibration ni son punitif.
func _update_shield_blink(delta: float) -> void:
	if _shield_blink_left <= 0.0:
		return
	_shield_blink_left -= delta
	var on := int(_shield_blink_left * 10) % 2 == 0
	for i in range(_shield_rect.size()):
		if i < shield:
			_shield_rect[i].color = UI.OK
		else:
			_shield_rect[i].color = UI.BAD if on else Color(0.25, 0.25, 0.3)
	if _shield_blink_left <= 0.0:
		_update_hud()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
