class_name IconButton
extends Control

## Round button with a vector icon and no text, so a child who cannot read can
## use it. The whole control rect is the hit area; the disc is drawn smaller
## inside it. Touch-down only shows feedback; the action fires on release
## inside the rect, so a resting palm or a finger sliding off does nothing.

signal pressed

## Hit area side in px: 12.7 mm at 430 dpi (216 / 16.93 px per mm).
const HIT := 216.0

@export var kind := "undo"
## Filled disc colour; transparent keeps the default glass disc.
var accent := Color(0, 0, 0, 0)
var disabled := false
var _held := false
var _press := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(HIT, HIT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = not disabled
		elif _held:
			_held = false
			if not disabled and Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
		_set_press(1.0 if _held else 0.0)
		accept_event()
	elif event is InputEventMouseMotion and _held:
		var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
		_set_press(1.0 if inside else 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _held:
		_set_press(0.0)


func _set_press(v: float) -> void:
	if _press != v:
		_press = v
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rad := minf(size.x, size.y) * 0.36 * (1.0 - 0.1 * _press)
	var alpha := 0.35 if disabled else 1.0
	if accent.a > 0.0:
		var fill := accent.darkened(0.2) if _press > 0.0 else accent
		draw_circle(c, rad, Color(fill, fill.a * alpha))
	else:
		draw_circle(c, rad, Color(1, 1, 1, (0.13 + 0.22 * _press) * alpha))
	draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, (0.35 + 0.5 * _press) * alpha), 4.0, true)
	# Icons are drawn in a 100 px design box around the centre, then scaled.
	var k := rad / 50.0
	draw_set_transform(c, 0.0, Vector2(k, k))
	var ink := Color(0.95, 0.98, 1.0, alpha)
	match kind:
		"undo":
			_draw_undo(ink)
		"restart":
			draw_arc(Vector2.ZERO, 22, PI * 0.35, PI * 1.95, 28, ink, 7.0, true)
			var tip2 := Vector2(22, -4)
			_tri(tip2 + Vector2(-12, -6), tip2 + Vector2(12, -6), tip2 + Vector2(0, 10), ink)
		"add":
			_draw_add(ink)
		"next":
			draw_line(Vector2(-24, 0), Vector2(8, 0), ink, 14.0)
			_tri(Vector2(2, -26), Vector2(30, 0), Vector2(2, 26), ink)
		"star":
			_draw_star(ink)
		"sound_on", "sound_off":
			_draw_sound(ink)
	draw_set_transform(Vector2.ZERO)


## Curved arrow bending back to the left.
func _draw_undo(ink: Color) -> void:
	draw_arc(Vector2(4, 6), 22, PI * 1.05, PI * 2.25, 24, ink, 7.0, true)
	var tip := Vector2(-18, 2)
	_tri(tip + Vector2(-12, 2), tip + Vector2(12, -2), tip + Vector2(-2, 18), ink)


## A small bottle with a plus beside it.
func _draw_add(ink: Color) -> void:
	var r := 11.0
	var pts := PackedVector2Array([Vector2(-22 - r, -26)])
	for i in range(0, 19):
		var a := PI - PI * i / 18.0
		pts.append(Vector2(-22 + r * cos(a), 20 + r * sin(a)))
	pts.append(Vector2(-22 + r, -26))
	draw_polyline(pts, ink, 5.0, true)
	draw_line(Vector2(-22 - r - 5, -26), Vector2(-22 + r + 5, -26), ink, 5.0)
	draw_rect(Rect2(-22 - r + 4, 4, 2 * r - 8, 20), Color(ink, 0.6 * ink.a))
	draw_line(Vector2(18, -14), Vector2(18, 14), ink, 7.0)
	draw_line(Vector2(4, 0), Vector2(32, 0), ink, 7.0)


func _draw_star(ink: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + PI * i / 5.0
		var rr := 34.0 if i % 2 == 0 else 14.0
		pts.append(Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.3, ink.a))


func _draw_sound(ink: Color) -> void:
	var sp := PackedVector2Array(
		[
			Vector2(-26, -10),
			Vector2(-14, -10),
			Vector2(2, -24),
			Vector2(2, 24),
			Vector2(-14, 10),
			Vector2(-26, 10)
		]
	)
	draw_colored_polygon(sp, ink)
	if kind == "sound_on":
		draw_arc(Vector2(4, 0), 14, -0.9, 0.9, 12, ink, 5.0, true)
		draw_arc(Vector2(4, 0), 26, -0.9, 0.9, 16, ink, 5.0, true)
	else:
		draw_line(Vector2(10, -12), Vector2(30, 12), ink, 6.0)
		draw_line(Vector2(30, -12), Vector2(10, 12), ink, 6.0)


func _tri(a: Vector2, b: Vector2, c: Vector2, ink: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), ink)
