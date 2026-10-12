## One level being played: owns the run, feeds it the player's steering, shows the HUD and the
## pause / fail / win cards. In attract mode a bot plays behind the menu and there is no HUD.
extends Node3D

signal leave(action: String)   # "next", "map", "menu"

const B := preload("res://scripts/core/balance.gd")
const Sim := preload("res://scripts/core/sim.gd")
const Bot := preload("res://scripts/core/bot.gd")
const LevelDb := preload("res://scripts/core/level_db.gd")
const LevelView := preload("res://scripts/game/level_view.gd")
const Kit := preload("res://scripts/ui/kit.gd")

enum Phase { PLAY, PAUSED, DOWN, FAILED, WON }
const LIVES := 3

var level := 1            # 1-based
var attract := false

var track: RefCounted
var sim: RefCounted
var view: Node3D
var phase := Phase.PLAY
var lives := LIVES
var _steer := 0.0
var _touch := -1
var _anchor_x := 0.0
var _prev := Vector3.ZERO
var _down_timer := 0.0
var _continued := false
var _doubled := false
var _result := {}

var _layer: CanvasLayer
var _hud: Control
var _crystal_label: Label
var _lives_label: Label
var _progress: ProgressBar
var _hint: Label
var _toast: Label
var _toast_left := 0.0
var _card: Control

func _ready() -> void:
	track = LevelDb.track(level - 1)
	sim = Sim.new(track)
	view = LevelView.new()
	add_child(view)
	view.setup(track, sim, LevelDb.world_index(level - 1), Progress.skin)
	_prev = Vector3(sim.s, sim.d, sim.h)
	if not attract:
		_build_hud()
		_show_hint()

# --- Input --------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if attract or phase != Phase.PLAY:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_anchor_x = event.position.x
			_steer = 0.0
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_steer = 0.0
	elif event is InputEventScreenDrag and event.index == _touch:
		# A sliding joystick: full steer at about a seventh of the screen width, and the
		# anchor follows the finger so a change of direction answers at once.
		var reach := get_viewport().get_visible_rect().size.x * 0.14 / Progress.sensitivity
		var dx: float = event.position.x - _anchor_x
		if dx > reach:
			_anchor_x = event.position.x - reach
		elif dx < -reach:
			_anchor_x = event.position.x + reach
		_steer = clampf((event.position.x - _anchor_x) / reach, -1.0, 1.0)

func _notification(what: int) -> void:
	if attract:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if phase == Phase.PLAY:
			_pause()

## Android back / Esc.
func back() -> void:
	match phase:
		Phase.PLAY, Phase.DOWN:
			_pause()
		Phase.PAUSED:
			_resume()
		_:
			leave.emit("map")

# --- Simulation ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if phase == Phase.DOWN:
		_down_timer -= B.STEP
		if _down_timer <= 0.0:
			sim.respawn()
			_drain()
			_prev = Vector3(sim.s, sim.d, sim.h)
			phase = Phase.PLAY
		return
	if phase != Phase.PLAY:
		return
	var steer := _steer
	if attract:
		steer = Bot.steer(sim, 1.0)
	elif _touch == -1:
		steer = Input.get_axis("ui_left", "ui_right")
	_prev = Vector3(sim.s, sim.d, sim.h)
	sim.step(steer)
	_drain()
	if sim.state == Sim.State.LOST:
		_on_lost()
	elif sim.state == Sim.State.WON:
		_on_won()

func _drain() -> void:
	for e in sim.events:
		view.on_event(e)
		if attract:
			continue
		match e["t"]:
			"crystal":
				Sound.play("crystal", 1.0 + minf(sim.crystals, 12) * 0.03)
				Sound.buzz(12)
			"hit":
				Sound.play("hit")
				Sound.buzz(45)
			"fall":
				Sound.play("fall")
			"launch":
				Sound.play("launch")
			"land":
				Sound.play("land")
			"boost":
				Sound.play("boost")
			"crumble":
				if e["col"] == 3 or e["col"] == 1:
					Sound.play("crumble")
			"checkpoint":
				Sound.play("checkpoint")
				Sound.buzz(25)
				_say(Loc.t("checkpoint"))
	sim.events.clear()

func _process(delta: float) -> void:
	var k := Engine.get_physics_interpolation_fraction() if phase == Phase.PLAY else 1.0
	var now := Vector3(sim.s, sim.d, sim.h)
	var p := _prev.lerp(now, k)
	view.present(delta, _steer, p.x, p.y, p.z)
	if attract:
		return
	_crystal_label.text = "◆ %d / %d" % [sim.crystals, track.crystals.size()]
	_lives_label.text = "♥".repeat(lives)
	_progress.value = sim.progress()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left * 2.0, 0.0, 1.0)
	if _hint.visible and sim.s > 60.0:
		_hint.modulate.a = maxf(_hint.modulate.a - delta * 1.5, 0.0)

func _on_lost() -> void:
	if attract:
		sim.respawn()
		_drain()
		return
	lives -= 1
	Sound.buzz(80)
	if lives > 0:
		phase = Phase.DOWN
		_down_timer = 0.55
	else:
		phase = Phase.FAILED
		Sound.play("lose")
		_show_failed()

func _on_won() -> void:
	if attract:
		restart()
		return
	phase = Phase.WON
	Sound.play("win")
	Sound.buzz(60)
	_result = Progress.finish_level(level, sim.stars(), sim.time, sim.crystals)
	Ads.note_level_finished()
	get_tree().create_timer(0.9).timeout.connect(_show_won)

func restart() -> void:
	sim = Sim.new(track)
	view.rebind(sim)
	_prev = Vector3(sim.s, sim.d, sim.h)
	lives = LIVES
	_continued = false
	_doubled = false
	_steer = 0.0
	_touch = -1
	phase = Phase.PLAY
	_close_card()

# --- HUD and cards ------------------------------------------------------------------------

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_hud)
	var top := Kit.top_inset(self) + 18.0

	var pause := Kit.button("II", "ghost", 30, 84)
	pause.custom_minimum_size = Vector2(84, 84)
	pause.position = Vector2(20, top)
	pause.pressed.connect(_pause)
	_hud.add_child(pause)

	var title := Kit.label(Loc.f("level_n", level), 26, Kit.DIM)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = top + 4
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(title)

	_crystal_label = Kit.label("", 34, Kit.CYAN)
	_crystal_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_crystal_label.position.y = top + 36
	_crystal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_crystal_label)

	_lives_label = Kit.label("", 36, Kit.RED, false)
	_lives_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lives_label.position = Vector2(-150, top + 16)
	_lives_label.custom_minimum_size = Vector2(130, 0)
	_lives_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_lives_label)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progress.offset_left = 120
	_progress.offset_right = -120
	_progress.offset_top = top + 96
	_progress.offset_bottom = top + 106
	for part in [["background", Color(1, 1, 1, 0.18)], ["fill", Kit.CYAN]]:
		var sb := Kit.box(part[1], 5)
		sb.set_content_margin_all(0)
		_progress.add_theme_stylebox_override(part[0], sb)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_progress)

	_hint = Kit.label("", 32, Kit.TEXT)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 40
	_hint.offset_right = -40
	_hint.position.y = -230
	_hint.add_theme_color_override("font_outline_color", Kit.INK)
	_hint.add_theme_constant_override("outline_size", 10)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)

	_toast = Kit.label("", 40, Kit.GOLD)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.position.y = top + 190
	_toast.add_theme_color_override("font_outline_color", Kit.INK)
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toast)

## The first levels teach by doing; one short line says what to try.
func _show_hint() -> void:
	var hints := {1: "hint_steer", 2: "hint_crystals", 3: "hint_edge", 4: "hint_gap", 5: "hint_checkpoint"}
	_hint.visible = hints.has(level) and Progress.stars_of(level) == 0
	if _hint.visible:
		_hint.text = Loc.t(hints[level])

func _say(text: String) -> void:
	_toast.text = text
	_toast_left = 1.4

func _set_card(content: Control) -> void:
	_close_card()
	_card = Kit.overlay(content)
	_layer.add_child(_card)

func _close_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null

func _pause() -> void:
	if phase != Phase.PLAY and phase != Phase.DOWN:
		return
	phase = Phase.PAUSED
	_touch = -1
	_steer = 0.0
	var v := Kit.vbox(18)
	v.add_child(Kit.label(Loc.t("pause"), 48))
	v.add_child(Kit.label(Loc.f("level_n", level), 26, Kit.DIM))
	var resume := Kit.button(Loc.t("resume"), "primary", 36, 104)
	resume.pressed.connect(_resume)
	v.add_child(resume)
	var again := Kit.button(Loc.t("restart"))
	again.pressed.connect(restart)
	v.add_child(again)
	var map := Kit.button(Loc.t("to_map"), "ghost")
	map.pressed.connect(func() -> void: leave.emit("map"))
	v.add_child(map)
	_set_card(v)

func _resume() -> void:
	_close_card()
	phase = Phase.PLAY if sim.state == Sim.State.RUNNING or sim.state == Sim.State.FALLING else Phase.DOWN

func _show_failed() -> void:
	var v := Kit.vbox(18)
	v.add_child(Kit.label(Loc.t("no_lives"), 44))
	v.add_child(Kit.label("%s  ·  ◆ %d" % [Loc.f("level_n", level), sim.crystals], 26, Kit.DIM))
	var again := Kit.button(Loc.t("retry"), "primary", 38, 112)
	again.pressed.connect(restart)
	v.add_child(again)
	# One voluntary second chance per attempt, only when an ad is actually ready.
	if not _continued and Ads.rewarded_ready():
		var more := Kit.button("▶  " + Loc.t("continue_ad"), "gold", 28)
		more.pressed.connect(_continue_with_ad.bind(more))
		v.add_child(more)
	var map := Kit.button(Loc.t("to_map"), "ghost")
	map.pressed.connect(func() -> void: leave.emit("map"))
	v.add_child(map)
	_set_card(v)

func _continue_with_ad(button: Button) -> void:
	button.disabled = true
	Ads.show_rewarded(func(earned: bool) -> void:
		if not is_inside_tree():
			return
		if earned and phase == Phase.FAILED and not _continued:
			_continued = true
			lives = LIVES
			sim.respawn()
			_drain()
			_prev = Vector3(sim.s, sim.d, sim.h)
			_close_card()
			phase = Phase.PLAY
		else:
			button.disabled = false
			if not earned:
				_say(Loc.t("ad_unavailable")))

func _show_won() -> void:
	if phase != Phase.WON:
		return
	var stars: int = sim.stars()
	var v := Kit.vbox(14)
	v.add_child(Kit.label(Loc.t("level_done"), 44))
	var star_label := Kit.label(Kit.stars_text(stars), 84, Kit.GOLD)
	v.add_child(star_label)
	Sound.play("star")
	var goal2 := Loc.f("star_2", track.star_crystals)
	var goal3 := Loc.t("star_3") if track.par_time <= 0.0 else Loc.f("star_3_time", int(track.par_time))
	v.add_child(Kit.label("%s  %s\n%s  %s" % ["★" if stars >= 2 else "☆", goal2, "★" if stars >= 3 else "☆", goal3], 24, Kit.DIM))
	var line := "%s: %.1f s" % [Loc.t("time"), sim.time]
	if _result.get("record", false) and not _result.get("first", false):
		line += "   " + Loc.t("record")
	v.add_child(Kit.label(line, 26, Kit.TEXT))
	var reward_label := Kit.label("%s: ◆ %d" % [Loc.t("reward"), int(_result.get("reward", 0))], 34, Kit.CYAN)
	v.add_child(reward_label)
	for id in _result.get("skins", []):
		v.add_child(Kit.label(Loc.f("new_skin", Loc.t("skin_" + str(id))), 28, Kit.GREEN))
	var last: bool = level >= LevelDb.count()
	var next := Kit.button(Loc.t("campaign_done") if last else Loc.t("next"), "primary", 38, 112)
	next.pressed.connect(func() -> void: _leave_after_ad("map" if last else "next"))
	v.add_child(next)
	if Ads.rewarded_ready() and int(_result.get("reward", 0)) > 0:
		var twice := Kit.button("▶  " + Loc.t("double_ad"), "gold", 28)
		twice.pressed.connect(_double_with_ad.bind(twice, reward_label))
		v.add_child(twice)
	var row := Kit.hbox(14)
	var again := Kit.button(Loc.t("restart"), "ghost", 28)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(restart)
	row.add_child(again)
	var map := Kit.button(Loc.t("to_map"), "ghost", 28)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.pressed.connect(func() -> void: _leave_after_ad("map"))
	row.add_child(map)
	v.add_child(row)
	_set_card(v)

func _double_with_ad(button: Button, reward_label: Label) -> void:
	button.disabled = true
	Ads.show_rewarded(func(earned: bool) -> void:
		if not is_inside_tree():
			return
		if earned and not _doubled:
			_doubled = true
			var bonus := int(_result.get("reward", 0))
			Progress.add_crystals(bonus)
			reward_label.text = "%s: ◆ %d" % [Loc.t("reward"), bonus * 2]
			button.visible = false
			Sound.play("crystal")
		else:
			button.disabled = false
			if not earned:
				_say(Loc.t("ad_unavailable")))

## Between levels is the only place an interstitial may appear.
func _leave_after_ad(action: String) -> void:
	Ads.maybe_interstitial(Progress.levels_done, func() -> void:
		if is_inside_tree():
			leave.emit(action))
