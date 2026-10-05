extends Node

## Dev-only: boots the game, checks a real touch selects a bottle, checks the
## buttons fire on release only, prints every hit area in mm, then plays a
## solver-found solution through the tap API and saves screenshots, last with
## a fake 120 px top cutout. Run under Xvfb. CAPTURE_SHELL=1 runs it as if
## inside MWM Play (no sound button).

var out_dir: String = OS.get_environment("CAPTURE_DIR")


func _ready() -> void:
	if OS.get_environment("CAPTURE_SHELL") == "1":
		Engine.set_meta(&"mwm_play_shell", true)
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(5)
	game.start_level(1)
	await _frames(10)
	await _shot("00_level1")
	_measure(game, "level 1")
	await _check_release(game)

	var lvl := (
		int(OS.get_environment("CAPTURE_LEVEL")) if OS.has_environment("CAPTURE_LEVEL") else 8
	)
	game.start_level(lvl)
	await _frames(10)
	await _shot("01_start")
	_measure(game, "level %d" % lvl)

	var target := -1
	for i in range(game.tubes.size()):
		if not game.tubes[i].is_empty():
			target = i
			break
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	var hr: Rect2 = game.bottles[target].hit_rect()
	# Tap the padded edge of the hit area, outside the drawn glass.
	touch.position = Vector2(hr.position.x + 6, hr.get_center().y)
	Input.parse_input_event(touch)
	await _frames(15)
	print("TOUCH at padded edge selects bottle: ", game.selected == target)
	await _shot("02_selected")
	game.tap(target)
	await _frames(15)

	var moves: Variant = Puzzle.solve(game.tubes)
	print("SOLUTION moves: ", moves.size())
	var k := 0
	for m in moves:
		while game.bottles[m[0]].busy or game.bottles[m[1]].busy:
			await _frames(1)
		game.tap(m[0])
		await _frames(3)
		game.tap(m[1])
		if k == 0:
			await _frames(28)
			await _shot("03_pouring")
		k += 1
	while game._any_busy():
		await _frames(1)
	await _frames(40)
	print("SOLVED: ", Puzzle.is_solved(game.tubes), " won: ", game.won)
	await _shot("04_win_confetti")
	await _frames(60)
	await _shot("05_win_panel")
	var nr: Rect2 = game.btn_next.get_global_rect()
	print("HIT next: %s" % _mm(nr))
	await _click(nr.get_center(), nr.get_center())
	await _frames(10)
	print("NEXT on release -> level ", game.level)
	game.add_bottle()
	await _frames(30)
	await _shot("06_next_level_extra_bottle")
	_measure(game, "level %d + extra" % game.level)
	game.start_level(30)
	await _frames(10)
	await _shot("07_level30")
	_measure(game, "level 30")
	game.add_bottle()
	await _frames(30)
	await _shot("08_level30_extra")
	_measure(game, "level 30 + extra")
	# Fake 120 px camera cutout: top row moves down, hit areas keep the edge.
	game.start_level(8)
	game.fake_safe_top = 120.0
	game._on_resize()
	await _frames(10)
	await _shot("09_inset120_level8")
	_measure(game, "level 8, fake 120 px top inset")
	print("INSET level label top y %.0f" % game.level_label.position.y)
	game.fake_safe_top = -1.0
	game._on_resize()
	await _frames(30)
	var cfg := ConfigFile.new()
	print(
		"SAVE ",
		game.SAVE_PATH,
		" load=",
		cfg.load(game.SAVE_PATH),
		" level=",
		cfg.get_value("game", "level", -1)
	)
	get_tree().quit()


func _check_release(game: Node) -> void:
	var r: Rect2 = game.btn_add.get_global_rect()
	await _press(r.get_center(), true)
	var after_down: bool = game.extra_used
	await _press(r.get_center(), false)
	print("ADD fires on down: ", after_down, ", after release: ", game.extra_used)
	await _frames(20)
	game.start_level(1)
	await _frames(5)
	await _press(r.get_center(), true)
	await _shot("00b_add_held")
	var out := Vector2(r.get_center().x, r.position.y - 60)
	var mm := InputEventMouseMotion.new()
	mm.position = out
	mm.global_position = out
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)
	await _frames(2)
	await _press(out, false)
	print("ADD slide-off release fires: ", game.extra_used)
	game.start_level(1)
	await _frames(5)


func _click(a: Vector2, b: Vector2) -> void:
	await _press(a, true)
	await _press(b, false)


func _press(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
	await _frames(3)


func _measure(game: Node, label: String) -> void:
	print("== hit areas, ", label, " (", game.bottles.size(), " bottles)")
	for n in ["btn_restart", "btn_sound", "btn_undo", "btn_add"]:
		var b: Control = game.get(n)
		print("HIT %s visible=%s %s" % [n, b.visible, _mm(b.get_global_rect())])
	var rects: Array = []
	var min_w := INF
	for i in range(game.bottles.size()):
		var r: Rect2 = game.bottles[i].hit_rect()
		rects.append(r)
		min_w = minf(min_w, r.size.x)
	var overlaps := 0
	var bottom := 0.0
	for i in range(rects.size()):
		bottom = maxf(bottom, rects[i].end.y)
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	print("HIT bottle0 %s" % _mm(rects[0]))
	print(
		(
			"BOTTLES min_w=%.0f px (%.1f mm@400, %.1f mm@430) overlaps=%d lowest_y=%.0f"
			% [min_w, min_w * 25.4 / 400.0, min_w * 25.4 / 430.0, overlaps, bottom]
		)
	)


func _mm(r: Rect2) -> String:
	return (
		"(%.0f,%.0f) %.0fx%.0f px = %.1fx%.1f mm@400, %.1fx%.1f mm@430, bottom y %.0f"
		% [
			r.position.x,
			r.position.y,
			r.size.x,
			r.size.y,
			r.size.x * 25.4 / 400.0,
			r.size.y * 25.4 / 400.0,
			r.size.x * 25.4 / 430.0,
			r.size.y * 25.4 / 430.0,
			r.end.y
		]
	)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
