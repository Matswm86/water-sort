class_name IconButton
extends Control

## Round button with a vector icon and an optional caption below it.

signal pressed

@export var kind := "undo"
var caption := ""
var disabled := false
var _press := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(130, 130)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not disabled:
			_press = 1.0
			queue_redraw()
			pressed.emit()
			var tw := create_tween()
			tw.tween_property(self, "_press", 0.0, 0.18)
			tw.tween_callback(queue_redraw)
		accept_event()


func _process(_delta: float) -> void:
	if _press > 0.0:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 54)
	var rad := 50.0 * (1.0 - 0.08 * _press)
	var alpha := 0.35 if disabled else 1.0
	draw_circle(c, rad, Color(1, 1, 1, 0.13 * alpha))
	draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.35 * alpha), 3.0, true)
	var ink := Color(0.95, 0.98, 1.0, alpha)
	match kind:
		"undo":
			draw_arc(c + Vector2(4, 4), 22, PI * 1.05, PI * 2.25, 24, ink, 7.0, true)
			var tip := c + Vector2(-18, 0)
			draw_colored_polygon(
				PackedVector2Array(
					[tip + Vector2(-12, 2), tip + Vector2(12, -2), tip + Vector2(-2, 18)]
				),
				ink
			)
		"restart":
			draw_arc(c, 22, PI * 0.35, PI * 1.95, 28, ink, 7.0, true)
			var tip2 := c + Vector2(22, -4)
			draw_colored_polygon(
				PackedVector2Array(
					[tip2 + Vector2(-12, -6), tip2 + Vector2(12, -6), tip2 + Vector2(0, 10)]
				),
				ink
			)
		"add":
			var b := Rect2(c + Vector2(-26, -26), Vector2(26, 52))
			draw_rect(b, ink, false, 5.0)
			draw_line(c + Vector2(18, -14), c + Vector2(18, 14), ink, 7.0)
			draw_line(c + Vector2(4, 0), c + Vector2(32, 0), ink, 7.0)
		"sound_on", "sound_off":
			var sp := PackedVector2Array(
				[
					c + Vector2(-26, -10),
					c + Vector2(-14, -10),
					c + Vector2(2, -24),
					c + Vector2(2, 24),
					c + Vector2(-14, 10),
					c + Vector2(-26, 10)
				]
			)
			draw_colored_polygon(sp, ink)
			if kind == "sound_on":
				draw_arc(c + Vector2(4, 0), 14, -0.9, 0.9, 12, ink, 5.0, true)
				draw_arc(c + Vector2(4, 0), 26, -0.9, 0.9, 16, ink, 5.0, true)
			else:
				draw_line(c + Vector2(10, -12), c + Vector2(30, 12), ink, 6.0)
				draw_line(c + Vector2(30, -12), c + Vector2(10, 12), ink, 6.0)
	if caption != "":
		var font := get_theme_default_font()
		var fs := 28
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(
			font,
			Vector2(size.x * 0.5 - w * 0.5, 112 + fs * 0.4),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Color(1, 1, 1, 0.8 * alpha)
		)
