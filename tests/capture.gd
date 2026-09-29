extends Node

## Dev-only: boots the game, checks a real touch selects a bottle, then plays a
## solver-found solution through the tap API and saves screenshots. Run under Xvfb.

var out_dir: String = OS.get_environment("CAPTURE_DIR")


func _ready() -> void:
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await _frames(5)
	var lvl := (
		int(OS.get_environment("CAPTURE_LEVEL")) if OS.has_environment("CAPTURE_LEVEL") else 8
	)
	game.start_level(lvl)
	await _frames(10)
	await _shot("01_start")

	var target := -1
	for i in range(game.tubes.size()):
		if not game.tubes[i].is_empty():
			target = i
			break
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = game.bottles[target].home + Vector2(0, 120)
	Input.parse_input_event(touch)
	await _frames(15)
	print("TOUCH selects bottle: ", game.selected == target)
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
	game.undo()
	game.next_level()
	await _frames(10)
	game.add_bottle()
	await _frames(30)
	await _shot("06_next_level_extra_bottle")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
