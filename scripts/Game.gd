extends Node2D

## Water Sort: tap a bottle, tap another, the top color pours across when it
## matches or the target is empty. Endless seeded levels, free undo, one extra
## bottle per level. No ads, no network, no tracking.

const PALETTE := [
	Color("e8413c"),  # red
	Color("f28a2e"),  # orange
	Color("f5d63a"),  # yellow
	Color("9bd93b"),  # lime
	Color("2e9e4f"),  # green
	Color("1fb5a8"),  # teal
	Color("6fd0f5"),  # sky
	Color("2f5fe0"),  # blue
	Color("f272b6"),  # pink
	Color("8b5a2b"),  # brown
	Color("8e44c9"),  # purple
	Color("f7ead0"),  # cream
]
const SAVE_PATH := "user://save.cfg"
const LIFT := 42.0

var level := 1
var tubes: Array = []
var bottles: Array = []
var selected := -1
var history: Array = []
var extra_used := false
var won := false
var sound_on := true
## Active pour streams keyed by source bottle index.
var streams := {}

var bottle_layer: Node2D
var fx_layer: Node2D
var ui: CanvasLayer
var level_label: Label
var btn_undo: IconButton
var btn_add: IconButton
var btn_restart: IconButton
var btn_sound: IconButton
var win_panel: ColorRect
var win_title: Label
var music: AudioStreamPlayer
var sfx := {}


func _ready() -> void:
	_load()
	bottle_layer = Node2D.new()
	add_child(bottle_layer)
	fx_layer = Node2D.new()
	fx_layer.z_index = 20
	fx_layer.draw.connect(_draw_streams)
	add_child(fx_layer)
	_build_ui()
	_build_audio()
	get_viewport().size_changed.connect(_on_resize)
	start_level(level)


func _on_resize() -> void:
	queue_redraw()
	_layout_ui()
	_layout_bottles(false)


# --- level flow -------------------------------------------------------------


func start_level(n: int) -> void:
	level = n
	tubes = Puzzle.generate(level)
	history.clear()
	streams.clear()
	extra_used = false
	won = false
	selected = -1
	for b in bottles:
		b.queue_free()
	bottles.clear()
	for fx in fx_layer.get_children():
		fx.queue_free()
	for t in tubes:
		_add_bottle(t)
	win_panel.visible = false
	_layout_bottles(false)
	_refresh_ui()


func _add_bottle(tube: Array) -> void:
	var b := Bottle.new()
	b.palette = PALETTE
	b.set_from_tube(tube)
	bottle_layer.add_child(b)
	bottles.append(b)


func _layout_bottles(animate: bool) -> void:
	var n := bottles.size()
	if n == 0:
		return
	var vs := get_viewport_rect().size
	var rows := 1 if n <= 5 else 2
	var per := ceili(float(n) / rows)
	var top := 330.0
	var bottom := vs.y - 280.0
	var bottle_h := Bottle.HB + 16.0
	var cell_w := minf(vs.x - 40.0, 1060.0) / per
	var gap := 120.0
	var sc := minf(1.2, cell_w / (Bottle.W + 46.0))
	sc = minf(sc, (bottom - top) / (rows * bottle_h + (rows - 1) * gap))
	var total_h := rows * bottle_h * sc + (rows - 1) * gap * sc
	var y0 := top + ((bottom - top) - total_h) * 0.5
	var idx := 0
	for r in range(rows):
		var count := per if r < rows - 1 else n - per * (rows - 1)
		for k in range(count):
			var b: Bottle = bottles[idx]
			var x := vs.x * 0.5 + (k - (count - 1) * 0.5) * cell_w
			b.home = Vector2(x, y0 + r * (bottle_h + gap) * sc)
			b.scale = Vector2(sc, sc)
			var dest := b.home - Vector2(0, LIFT * sc) if idx == selected else b.home
			if animate and not b.busy:
				create_tween().tween_property(b, "position", dest, 0.25).set_trans(Tween.TRANS_SINE)
			elif not b.busy:
				b.position = dest
			b.set_corked(Puzzle.is_complete(tubes[idx]), false)
			idx += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not won:
		tap(_bottle_at(event.position))


func _bottle_at(p: Vector2) -> int:
	for i in range(bottles.size()):
		if bottles[i].hit_rect().has_point(p):
			return i
	return -1


func tap(i: int) -> void:
	if won:
		return
	if i < 0:
		_deselect()
		return
	var b: Bottle = bottles[i]
	if selected == -1:
		if _selectable(i):
			_select(i)
		else:
			_shake(i)
	elif selected == i:
		_deselect()
	elif not b.busy and Puzzle.can_pour(tubes, selected, i):
		var from := selected
		selected = -1
		_pour(from, i)
	elif _selectable(i):
		_deselect()
		_select(i)
	else:
		_shake(i)
		_deselect()


func _selectable(i: int) -> bool:
	var b: Bottle = bottles[i]
	return not b.busy and not tubes[i].is_empty() and not Puzzle.is_complete(tubes[i])


func _select(i: int) -> void:
	selected = i
	var b: Bottle = bottles[i]
	create_tween().tween_property(b, "position", b.home - Vector2(0, LIFT * b.scale.x), 0.14)
	_play("tap")


func _deselect() -> void:
	if selected == -1:
		return
	var b: Bottle = bottles[selected]
	selected = -1
	if not b.busy:
		create_tween().tween_property(b, "position", b.home, 0.14)


func _shake(i: int) -> void:
	var b: Bottle = bottles[i]
	if b.busy or i == selected:
		return
	var tw := create_tween()
	for dx in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tw.tween_property(b, "position", b.home + Vector2(dx, 0), 0.05)


func _any_busy() -> bool:
	for b in bottles:
		if b.busy:
			return true
	return false


# --- pouring ----------------------------------------------------------------


func _pour(from: int, to: int) -> void:
	var n := Puzzle.pour_amount(tubes, from, to)
	var color: int = tubes[from].back()
	for k in range(n):
		tubes[to].append(tubes[from].pop_back())
	history.append([from, to, n])
	_refresh_ui()
	await _animate_pour(from, to, color, n)
	if Puzzle.is_complete(tubes[to]):
		bottles[to].set_corked(true, true)
		_sparkle(bottles[to], PALETTE[color])
		_play("done")
	if Puzzle.is_solved(tubes) and not won and not _any_busy():
		_win()
	_refresh_ui()


static func _tilt_for(units: float) -> float:
	return 52.0 + (Puzzle.CAP - units) * 10.5


func _animate_pour(from: int, to: int, color: int, n: int) -> void:
	var b: Bottle = bottles[from]
	var tb: Bottle = bottles[to]
	b.busy = true
	tb.busy = true
	b.z_index = 10
	var sc := b.scale.x
	var side := 1.0 if tb.home.x >= b.home.x else -1.0
	var corner := Vector2(side * Bottle.W * 0.5, 0)
	var f0 := b.fill()
	var a0 := deg_to_rad(_tilt_for(f0)) * side
	var a1 := deg_to_rad(_tilt_for(f0 - n) + 6.0) * side
	var anchor := tb.home + Vector2(0, -70.0 * tb.scale.x)
	var pose := func(a: float) -> Vector2: return anchor - (corner * sc).rotated(a)
	var start := b.position

	var tw := create_tween()
	(
		tw
		. tween_method(
			func(k: float) -> void:
				b.rotation = a0 * k
				b.position = start.lerp(pose.call(a0 * k), k),
			0.0,
			1.0,
			0.3
		)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	await tw.finished

	if tb.segs.is_empty() or tb.segs.back()[0] != color:
		tb.segs.append([color, 0.0])
	var src_seg: Array = b.segs.back()
	var dst_seg: Array = tb.segs.back()
	var src_start: float = src_seg[1]
	var dst_start: float = dst_seg[1]
	_play("pour", 0.9 + 0.08 * (tb.fill() + n))
	var col: Color = PALETTE[color]
	tw = create_tween()
	tw.tween_method(
		func(k: float) -> void:
			b.rotation = lerpf(a0, a1, k)
			b.position = pose.call(b.rotation)
			src_seg[1] = src_start - n * k
			dst_seg[1] = dst_start + n * k
			var lip := b.to_global(corner)
			var w := 13.0 * sc * clampf(minf(k, 1.0 - k) * 10.0, 0.0, 1.0)
			streams[from] = {
				"a": lip, "b": Vector2(lip.x, tb.surface_global().y), "color": col, "w": w
			}
			fx_layer.queue_redraw(),
		0.0,
		1.0,
		0.25 + 0.17 * n
	)
	await tw.finished
	streams.erase(from)
	fx_layer.queue_redraw()

	var p1 := b.position
	var r1 := b.rotation
	tw = create_tween()
	(
		tw
		. tween_method(
			func(k: float) -> void:
				b.rotation = lerpf(r1, 0.0, k)
				b.position = p1.lerp(b.home, k),
			0.0,
			1.0,
			0.3
		)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	await tw.finished
	b.z_index = 0
	b.busy = false
	tb.busy = false
	b.set_from_tube(tubes[from])
	tb.set_from_tube(tubes[to])


func _draw_streams() -> void:
	for s in streams.values():
		if s["w"] > 0.5:
			fx_layer.draw_line(s["a"], s["b"], s["color"], s["w"], true)
			fx_layer.draw_circle(s["b"], s["w"] * 0.8, s["color"])


func _draw() -> void:
	var vs := get_viewport_rect().size
	var top := Color("1b4260")
	var bot := Color("0b1a28")
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
		PackedColorArray([top, top, bot, bot])
	)


# --- actions ----------------------------------------------------------------


func undo() -> void:
	if history.is_empty() or won or _any_busy():
		return
	_deselect()
	var m: Array = history.pop_back()
	for k in range(m[2]):
		tubes[m[0]].append(tubes[m[1]].pop_back())
	for i in [m[0], m[1]]:
		bottles[i].set_from_tube(tubes[i])
		bottles[i].set_corked(Puzzle.is_complete(tubes[i]), false)
	_play("tap")
	_refresh_ui()


func add_bottle() -> void:
	if extra_used or won or _any_busy():
		return
	extra_used = true
	tubes.append([])
	_add_bottle([])
	var b: Bottle = bottles.back()
	b.position = Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y)
	_layout_bottles(true)
	_play("tap")
	_refresh_ui()


func restart() -> void:
	if _any_busy():
		return
	start_level(level)


func _win() -> void:
	won = true
	_save()
	_play("win")
	_confetti()
	await get_tree().create_timer(0.9).timeout
	win_title.text = "Level %d\ncomplete!" % level
	win_panel.visible = true
	win_panel.modulate.a = 0.0
	create_tween().tween_property(win_panel, "modulate:a", 1.0, 0.3)


func next_level() -> void:
	start_level(level + 1)
	_save()


# --- effects ----------------------------------------------------------------


func _sparkle(b: Bottle, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = b.to_global(Vector2(0, -10))
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 65.0
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2(0, 1100)
	p.scale_amount_min = 7.0
	p.scale_amount_max = 13.0
	p.color = col.lightened(0.25)
	fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _confetti() -> void:
	var vs := get_viewport_rect().size
	var p := CPUParticles2D.new()
	p.position = Vector2(vs.x * 0.5, -40)
	p.one_shot = true
	p.amount = 180
	p.lifetime = 3.2
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vs.x * 0.5, 10)
	p.direction = Vector2.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2(0, 420)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 12.0
	p.scale_amount_max = 22.0
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for i in range(PALETTE.size()):
		grad.add_point(float(i) / PALETTE.size(), PALETTE[i])
	p.color_initial_ramp = grad
	fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(4.0).timeout.connect(p.queue_free)


# --- UI -----------------------------------------------------------------------


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	level_label = Label.new()
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 66)
	level_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(level_label)

	btn_restart = _make_button("restart", "", restart)
	btn_sound = _make_button("sound_on", "", _toggle_sound)
	btn_undo = _make_button("undo", "Undo", undo)
	btn_add = _make_button("add", "+1 Bottle", add_bottle)
	btn_add.custom_minimum_size = Vector2(170, 130)
	btn_add.size = btn_add.custom_minimum_size

	win_panel = ColorRect.new()
	win_panel.color = Color(0.02, 0.06, 0.1, 0.72)
	win_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(win_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 70)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.add_child(box)
	win_title = Label.new()
	win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_title.add_theme_font_size_override("font_size", 92)
	win_title.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	box.add_child(win_title)
	var next := Button.new()
	next.text = "Next"
	next.custom_minimum_size = Vector2(440, 150)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.add_theme_font_size_override("font_size", 64)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2fa36b") if state != "pressed" else Color("258555")
		sb.set_corner_radius_all(75)
		next.add_theme_stylebox_override(state, sb)
	next.add_theme_color_override("font_color", Color.WHITE)
	next.pressed.connect(next_level)
	box.add_child(next)
	win_panel.visible = false
	_layout_ui()


func _make_button(kind: String, caption: String, cb: Callable) -> IconButton:
	var b := IconButton.new()
	b.kind = kind
	b.caption = caption
	b.pressed.connect(cb)
	ui.add_child(b)
	return b


func _layout_ui() -> void:
	var vs := get_viewport_rect().size
	level_label.position = Vector2(0, 150)
	level_label.size = Vector2(vs.x, 90)
	# Right half, beside the sound button: the top-left 232 px square stays free
	# for the MWM Play home button.
	btn_restart.position = Vector2(vs.x - 314, 130)
	btn_sound.position = Vector2(vs.x - 164, 130)
	btn_undo.position = Vector2(vs.x * 0.5 - 200, vs.y - 230)
	btn_add.position = Vector2(vs.x * 0.5 + 40, vs.y - 230)
	win_panel.position = Vector2.ZERO
	win_panel.size = vs


func _refresh_ui() -> void:
	level_label.text = "Level %d" % level
	btn_undo.disabled = history.is_empty()
	btn_add.disabled = extra_used
	btn_sound.kind = "sound_on" if sound_on else "sound_off"
	for b in [btn_undo, btn_add, btn_sound]:
		b.queue_redraw()


func _toggle_sound() -> void:
	sound_on = not sound_on
	if sound_on:
		music.play()
	else:
		music.stop()
	_save()
	_refresh_ui()


# --- audio + save -------------------------------------------------------------


func _build_audio() -> void:
	for key in ["tap", "pour", "done", "win"]:
		var path := "res://assets/audio/%s.wav" % key
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.volume_db = -4.0
			add_child(p)
			sfx[key] = p
	music = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/music.wav"):
		music.stream = load("res://assets/audio/music.wav")
	music.volume_db = -12.0
	music.finished.connect(_on_music_finished)
	add_child(music)
	if sound_on and music.stream:
		music.play()


func _on_music_finished() -> void:
	if sound_on:
		music.play()


func _play(key: String, pitch: float = 1.0) -> void:
	if sound_on and sfx.has(key):
		sfx[key].pitch_scale = pitch
		sfx[key].play()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		level = int(cfg.get_value("game", "level", 1))
		sound_on = bool(cfg.get_value("game", "sound", true))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "level", level + 1 if won else level)
	cfg.set_value("game", "sound", sound_on)
	cfg.save(SAVE_PATH)
