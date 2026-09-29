class_name Bottle
extends Node2D

## One glass bottle. The origin sits at the centre of the mouth, so the bottle
## tilts around its opening. Liquid is drawn with a level surface whatever the
## tilt: each layer boundary is found by bisection so the layer keeps its volume.

const W := 88.0
const U := 62.0
const HEAD := 46.0
const CAP := 4
const HB := HEAD + CAP * U
const GLASS := 6.0

var palette: Array = []
## Visual runs, bottom first: [color_id, amount_in_units]. Animations edit these.
var segs: Array = []
var home := Vector2.ZERO
var busy := false
var corked := false
var cork_t := 1.0

var _inner: PackedVector2Array
var _outer: PackedVector2Array
var _unit_area := 1.0


func _init() -> void:
	_inner = _shape(W * 0.5, HB)
	_outer = _shape(W * 0.5 + GLASS, HB + GLASS)
	_unit_area = _area(_clip(_inner, Vector2.DOWN, HEAD)) / CAP


func _process(_delta: float) -> void:
	if busy or cork_t < 1.0:
		queue_redraw()


func set_from_tube(tube: Array) -> void:
	segs.clear()
	for c in tube:
		if not segs.is_empty() and segs.back()[0] == c:
			segs.back()[1] += 1.0
		else:
			segs.append([c, 1.0])
	queue_redraw()


func fill() -> float:
	var f := 0.0
	for s in segs:
		f += s[1]
	return f


## Global point where the liquid surface of this bottle currently sits (upright).
func surface_global() -> Vector2:
	return to_global(Vector2(0, HEAD + (CAP - fill()) * U))


func hit_rect() -> Rect2:
	var s := scale.x
	return Rect2(home + Vector2(-W * 0.5 - 22, -40) * s, Vector2(W + 44, HB + 70) * s)


func set_corked(on: bool, animate: bool) -> void:
	corked = on
	cork_t = 0.0 if animate and on else 1.0
	if animate and on:
		var tw := create_tween()
		tw.tween_property(self, "cork_t", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(
			Tween.EASE_OUT
		)
	queue_redraw()


func _draw() -> void:
	var r := W * 0.5
	# Glass back.
	draw_colored_polygon(_outer, Color(0.85, 0.95, 1.0, 0.10))
	# Liquid, gravity expressed in this node's local frame.
	var g := Vector2.DOWN.rotated(-global_rotation)
	var total := 0.0
	var upper := INF
	for s in segs:
		var amount: float = s[1]
		if amount <= 0.001:
			continue
		total += amount
		var t := _level_for(g, total)
		var poly := _clip(_inner, g, t)
		if upper != INF:
			poly = _clip(poly, -g, -upper)
		if poly.size() >= 3:
			var col: Color = palette[s[0]]
			draw_colored_polygon(poly, col)
		upper = t
	# Thin bright line on the liquid surface.
	if total > 0.01:
		var surf := _clip(_inner, g, upper - 5.0)
		surf = _clip(surf, -g, -upper)
		if surf.size() >= 3:
			draw_colored_polygon(surf, Color(1, 1, 1, 0.22))
	# Glass outline, open at the top, with a lip.
	var rim := Color(0.93, 0.97, 1.0, 0.9)
	draw_polyline(_open_outline(), rim, 5.0, true)
	draw_line(Vector2(-r - GLASS - 7, -1), Vector2(r + GLASS + 7, -1), rim, 7.0, true)
	# Gloss stripe.
	draw_line(Vector2(-r + 13, 22), Vector2(-r + 13, HB - r - 6), Color(1, 1, 1, 0.28), 7.0, true)
	draw_line(Vector2(-r + 25, 30), Vector2(-r + 25, 90), Color(1, 1, 1, 0.16), 4.0, true)
	if corked:
		_draw_cork(r)


func _draw_cork(r: float) -> void:
	var drop := (1.0 - cork_t) * -70.0
	var body := Rect2(-r + 8, -22 + drop, W - 16, 40)
	draw_rect(body, Color(0.72, 0.5, 0.3))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 8)), Color(0.84, 0.63, 0.42))
	draw_rect(body, Color(0.45, 0.3, 0.18), false, 3.0)


func _open_outline() -> PackedVector2Array:
	# _outer starts with the two mouth corners; walk the rest so the top stays open.
	var pts := PackedVector2Array()
	for i in range(1, _outer.size()):
		pts.append(_outer[i])
	pts.append(_outer[0])
	return pts


func _level_for(g: Vector2, units: float) -> float:
	var target := units * _unit_area
	var lo := INF
	var hi := -INF
	for p in _inner:
		lo = minf(lo, p.dot(g))
		hi = maxf(hi, p.dot(g))
	for i in range(22):
		var mid := (lo + hi) * 0.5
		if _area(_clip(_inner, g, mid)) > target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func _shape(r: float, hb: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-r, 0), Vector2(r, 0), Vector2(r, hb - r)])
	for i in range(1, 18):
		var a := PI * i / 18.0
		pts.append(Vector2(r * cos(a), hb - r + r * sin(a)))
	pts.append(Vector2(-r, hb - r))
	return pts


## Keeps the part of a convex polygon where dot(p, n) >= t.
static func _clip(poly: PackedVector2Array, n: Vector2, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cnt := poly.size()
	for i in range(cnt):
		var a := poly[i]
		var b := poly[(i + 1) % cnt]
		var da := a.dot(n) - t
		var db := b.dot(n) - t
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var cnt := poly.size()
	for i in range(cnt):
		a += poly[i].cross(poly[(i + 1) % cnt])
	return absf(a) * 0.5
