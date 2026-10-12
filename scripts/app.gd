## The whole application: one game node (a level being played, or a bot rolling behind the
## menus) and one interface layer with the menu, level map, ball shop and settings.
extends Node

const LevelDb := preload("res://scripts/core/level_db.gd")
const Game := preload("res://scripts/game/game.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Skins := preload("res://scripts/game/skins.gd")

const PRIVACY_URL := "https://shokhjakhon05.github.io/rolling-legends-privacy/"

var _game: Node3D
var _layer: CanvasLayer
var _screen: Control
var _screen_name := ""

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	# Screenshots and tests can jump straight to a screen: --shot=<screen>[:level]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_mode(arg.trim_prefix("--shot="))
			return
	show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()

func _back() -> void:
	if _screen_name == "game":
		_game.back()
	elif _screen_name == "menu":
		get_tree().quit()
	else:
		show_menu()

# --- Game node ----------------------------------------------------------------------------

func _start_game(level: int, attract: bool) -> void:
	if _game != null:
		_game.queue_free()
	_game = Game.new()
	_game.level = level
	_game.attract = attract
	add_child(_game)
	move_child(_game, 0)
	Sound.set_music(LevelDb.world_index(level - 1))
	if not attract:
		_game.leave.connect(_on_leave)

func _ensure_attract() -> void:
	if _game == null or not _game.attract:
		_start_game(1 + (Progress.next_level(LevelDb.count()) - 1) / 10 * 10, true)

func play(level: int) -> void:
	_set_screen("game", null)
	_start_game(level, false)

func _on_leave(action: String) -> void:
	match action:
		"next":
			play(mini(_game.level + 1, LevelDb.count()))
		"menu":
			show_menu()
		_:
			show_map()

# --- Screens ------------------------------------------------------------------------------

func _set_screen(name: String, content: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = content
	_screen_name = name
	if content != null:
		_layer.add_child(content)

func _page(title: String, with_back: bool = true) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.12, 0.62 if with_back else 0.3)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", int(Kit.top_inset(self)) + 26)
	margin.add_theme_constant_override("margin_bottom", 40)
	root.add_child(margin)
	var v := Kit.vbox(18)
	margin.add_child(v)
	if with_back:
		var bar := Kit.hbox(16)
		var back := Kit.button("‹", "ghost", 44, 84)
		back.custom_minimum_size = Vector2(84, 84)
		back.pressed.connect(show_menu)
		bar.add_child(back)
		var t := Kit.label(title, 42, Kit.TEXT, false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(t)
		bar.add_child(Kit.label("◆ %d" % Progress.crystals, 32, Kit.CYAN, false))
		v.add_child(bar)
	return [root, v]

func show_menu() -> void:
	_ensure_attract()
	var page := _page("", false)
	var v: VBoxContainer = page[1]
	v.add_child(Kit.spacer(90))
	var title := Kit.label("ROLLING\nLEGENDS", 92, Kit.TEXT)
	title.add_theme_color_override("font_outline_color", Kit.INK)
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_constant_override("line_spacing", -18)
	v.add_child(title)
	var tag := Kit.label(Loc.t("tagline"), 26, Kit.GOLD)
	tag.add_theme_color_override("font_outline_color", Kit.INK)
	tag.add_theme_constant_override("outline_size", 8)
	v.add_child(tag)
	v.add_child(Kit.spacer(0, true))
	var total := LevelDb.count()
	var next := Progress.next_level(total)
	var play_button := Kit.button("▶  %s  ·  %s" % [Loc.t("play"), Loc.f("level_n", next)], "primary", 40, 124)
	play_button.pressed.connect(func() -> void: play(next))
	v.add_child(play_button)
	var row := Kit.hbox(14)
	for item in [["levels", show_map], ["balls", show_shop], ["settings", show_settings]]:
		var b := Kit.button(Loc.t(item[0]), "plain", 26, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(item[1])
		row.add_child(b)
	v.add_child(row)
	v.add_child(Kit.label("★ %d / %d      ◆ %d" % [Progress.total_stars(), total * 3, Progress.crystals], 28, Kit.TEXT))
	v.add_child(Kit.spacer(20))
	_set_screen("menu", page[0])

func show_map() -> void:
	_ensure_attract()
	var page := _page(Loc.t("levels"))
	var v: VBoxContainer = page[1]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := Kit.vbox(22)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var total := LevelDb.count()
	var current := Progress.next_level(total)
	for w in 3:
		var panel := Kit.panel(Color(0.07, 0.11, 0.21, 0.92))
		var pv := Kit.vbox(14)
		panel.add_child(pv)
		var got := 0
		for n in range(w * 10 + 1, w * 10 + 11):
			got += Progress.stars_of(n)
		var head := Kit.hbox(10)
		var name := Kit.label(Loc.t("world_%d" % (w + 1)), 34, [Kit.GOLD, Color("ff9a52"), Color("ff6bf2")][w], false)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name)
		head.add_child(Kit.label("★ %d / 30" % got, 28, Kit.GOLD, false))
		pv.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		pv.add_child(grid)
		for n in range(w * 10 + 1, mini(w * 10 + 11, total + 1)):
			var open := Progress.unlocked(n)
			var stars := Progress.stars_of(n)
			var text := "%d\n%s" % [n, Kit.stars_text(stars)] if open else "%d\n🔒" % n
			var b := Kit.button(text, "primary" if n == current else ("plain" if open else "ghost"), 26, 108)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not open:
				b.text = "%d\n—" % n
				b.disabled = true
			else:
				b.pressed.connect(play.bind(n))
			grid.add_child(b)
		list.add_child(panel)
	_set_screen("map", page[0])

func show_shop() -> void:
	_ensure_attract()
	var page := _page(Loc.t("balls"))
	var v: VBoxContainer = page[1]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := Kit.vbox(14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s in Progress.SKINS:
		var id: String = s["id"]
		var state := Progress.skin_state(id)
		var panel := Kit.panel(Color(0.07, 0.11, 0.21, 0.92), 26)
		var row := Kit.hbox(18)
		panel.add_child(row)
		var swatch := _swatch(id)
		row.add_child(swatch)
		var info := Kit.vbox(4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(Kit.label(Loc.t("skin_" + id), 30, Kit.TEXT, false))
		var note := ""
		if state == "locked":
			note = Loc.f("need_level", int(s["need_level"])) if s.has("need_level") else Loc.f("need_stars", int(s["need_stars"]))
		elif state == "buy":
			note = "◆ %d" % int(s["price"])
		elif Progress.skin == id:
			note = Loc.t("selected")
		info.add_child(Kit.label(note, 24, Kit.GREEN if Progress.skin == id else Kit.DIM, false))
		row.add_child(info)
		if state == "owned" and Progress.skin != id:
			var pick := Kit.button(Loc.t("select"), "plain", 26, 80)
			pick.pressed.connect(func() -> void:
				Progress.select_skin(id)
				_apply_skin()
				show_shop())
			row.add_child(pick)
		elif state == "buy":
			var buy := Kit.button("◆ %d" % int(s["price"]), "gold", 26, 80)
			buy.disabled = Progress.crystals < int(s["price"])
			buy.pressed.connect(func() -> void:
				if Progress.buy_skin(id):
					Sound.play("checkpoint")
					_apply_skin()
				show_shop())
			row.add_child(buy)
		list.add_child(panel)
	_set_screen("shop", page[0])

func _apply_skin() -> void:
	if _game != null:
		_game.view.set_skin(Progress.skin)

## A round colour sample of a skin.
func _swatch(id: String) -> Control:
	var c: Dictionary = Skins.colors(id)
	var p := Panel.new()
	p.custom_minimum_size = Vector2(84, 84)
	p.add_theme_stylebox_override("panel", Kit.box(c["a"], 42, c["b"], 9))
	return p

func show_settings() -> void:
	_ensure_attract()
	var page := _page(Loc.t("settings"))
	var v: VBoxContainer = page[1]
	var panel := Kit.panel(Color(0.07, 0.11, 0.21, 0.92))
	var pv := Kit.vbox(18)
	panel.add_child(pv)
	v.add_child(panel)

	var sound := Kit.button("%s: %s" % [Loc.t("sound"), Loc.t("on" if Progress.sound else "off")])
	sound.pressed.connect(func() -> void:
		Progress.sound = not Progress.sound
		Progress.save()
		show_settings())
	pv.add_child(sound)
	var music := Kit.button("%s: %s" % [Loc.t("music"), Loc.t("on" if Progress.music else "off")])
	music.pressed.connect(func() -> void:
		Progress.music = not Progress.music
		Progress.save()
		Sound.refresh_music()
		show_settings())
	pv.add_child(music)
	var vib := Kit.button("%s: %s" % [Loc.t("vibration"), Loc.t("on" if Progress.vibration else "off")])
	vib.pressed.connect(func() -> void:
		Progress.vibration = not Progress.vibration
		Progress.save()
		Sound.buzz(40)
		show_settings())
	pv.add_child(vib)

	pv.add_child(Kit.label("%s: %d%%" % [Loc.t("sensitivity"), int(round(Progress.sensitivity * 100))], 28, Kit.DIM))
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = Progress.sensitivity
	slider.custom_minimum_size = Vector2(0, 64)
	var value_label: Label = pv.get_child(pv.get_child_count() - 1)
	slider.value_changed.connect(func(x: float) -> void:
		Progress.sensitivity = x
		value_label.text = "%s: %d%%" % [Loc.t("sensitivity"), int(round(x * 100))])
	slider.drag_ended.connect(func(_c: bool) -> void: Progress.save())
	pv.add_child(slider)

	pv.add_child(Kit.label(Loc.t("language"), 28, Kit.DIM))
	var langs := Kit.hbox(12)
	for code in Loc.LANGS:
		var b := Kit.button(Loc.NAMES[code], "primary" if Loc.lang == code else "plain", 24, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			Progress.language = code
			Progress.save()
			Loc.refresh()
			show_settings())
		langs.add_child(b)
	pv.add_child(langs)

	v.add_child(Kit.spacer(0, true))
	if Ads.privacy_options_available():
		var choices := Kit.button(Loc.t("ad_choices"), "ghost", 26)
		choices.pressed.connect(Ads.show_privacy_options)
		v.add_child(choices)
	var privacy := Kit.button(Loc.t("privacy"), "ghost", 26)
	privacy.pressed.connect(func() -> void: OS.shell_open(PRIVACY_URL))
	v.add_child(privacy)
	v.add_child(Kit.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 22, Kit.DIM))
	_set_screen("settings", page[0])

# --- Screenshots --------------------------------------------------------------------------

## Opens one screen, lets it settle, saves a PNG and quits. Used by CI to show what a build
## looks like:  godot --path . -- --shot=game:8 --out=shots/level8.png --at=45
func _shot_mode(spec: String) -> void:
	Progress.persist = false
	var out := "shots/shot.png"
	var at := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--at="):
			at = float(arg.trim_prefix("--at="))
		elif arg.begins_with("--lang="):
			Progress.language = arg.trim_prefix("--lang=")
			Loc.refresh()
		elif arg.begins_with("--stars="):
			for n in range(1, int(arg.trim_prefix("--stars=")) + 1):
				Progress.stars[str(n)] = 2 + n % 2
			Progress.crystals = 420
	var parts := spec.split(":")
	match parts[0]:
		"game":
			play(int(parts[1]) if parts.size() > 1 else 1)
			# A bot rolls to the wanted spot so the picture shows real play.
			var bot := load("res://scripts/core/bot.gd")
			while _game.sim.s < at and _game.sim.state == 0:
				_game.sim.step(bot.steer(_game.sim, 1.0), bot.jump(_game.sim))
				for e in _game.sim.events:
					_game.view.on_event(e)
				_game.sim.events.clear()
			_game._prev = Vector3(_game.sim.s, _game.sim.d, _game.sim.h)
			_game.phase = _game.Phase.PAUSED
		"map":
			show_map()
		"shop":
			show_shop()
		"settings":
			show_settings()
		_:
			show_menu()
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit()
