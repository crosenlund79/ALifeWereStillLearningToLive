extends RefCounted
## RETRO SPECTRUM — a modern take on the classic LED spectrum analyzer.
##
## Stacked blocks per column (bass left, treble right) with a vertical colour gradient,
## lit blocks shaded top-to-bottom, a soft glow behind each active column, the top block lit
## fractionally for smooth motion, glowing peak caps that hold and then fall, and a faint
## reflection below. Colours: bottom/middle/top/peak from the element palette (defaults:
## green, gold, orange, rose). Settings: Columns, Block size, Peak hold, Glow, colours.

const Common := preload("res://vis/common.gd")
const ROWS := 18

var L: Control
var A: Node
var cols := 0
var height := PackedFloat32Array()
var peak := PackedFloat32Array()
var hold := PackedFloat32Array()
var poly := PackedVector2Array()
var poly_colors := PackedColorArray()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	poly.resize(4)
	poly_colors.resize(4)


func element_count() -> int:
	return cols * ROWS


func _ensure() -> void:
	var c := clampi(int(28 * L.p("density", 1.0)), 12, 56)
	if c != cols:
		cols = c
		height.resize(cols)
		peak.resize(cols)
		hold.resize(cols)
		height.fill(0.0)
		peak.fill(0.0)


func update(delta: float) -> void:
	_ensure()
	var levels: PackedFloat32Array = A.levels
	var per := float(levels.size()) / cols
	var hold_time: float = 0.15 + 1.0 * L.p("trail", 0.5)
	for c in cols:
		var target := 0.0
		for i in range(int(c * per), int((c + 1) * per)):
			target = maxf(target, levels[i])
		target = clampf(target * L.intensity, 0.0, 1.0)
		# Rise quickly, fall smoothly.
		height[c] = Common.approach(height[c], target, 30.0, delta) if target > height[c] else maxf(target, height[c] - delta * 1.2)
		if height[c] >= peak[c]:
			peak[c] = height[c]
			hold[c] = hold_time
		elif hold[c] > 0.0:
			hold[c] -= delta
		else:
			peak[c] = maxf(peak[c] - delta * 0.6, height[c])


## Block colour by height (0 bottom .. 1 top).
func _gradient(f: float) -> Color:
	var stops := [L.color(6), L.color(0), L.color(1), L.color(2)]
	var x := clampf(f, 0.0, 1.0) * 3.0
	var i := mini(int(x), 2)
	return (stops[i] as Color).lerp(stops[i + 1], x - i)


func _block(rect: Rect2, col: Color, alpha: float, shade := true) -> void:
	poly[0] = rect.position
	poly[1] = Vector2(rect.end.x, rect.position.y)
	poly[2] = rect.end
	poly[3] = Vector2(rect.position.x, rect.end.y)
	var top := Color(col.lightened(0.25) if shade else col, alpha)
	var bottom := Color(col.darkened(0.2) if shade else col, alpha)
	poly_colors[0] = top
	poly_colors[1] = top
	poly_colors[2] = bottom
	poly_colors[3] = bottom
	L.draw_polygon(poly, poly_colors)


func draw() -> void:
	if cols == 0:
		return
	var area := Rect2(L.size * Vector2(0.1, 0.2), L.size * Vector2(0.8, 0.5))
	var cell := Vector2(area.size.x / cols, area.size.y / ROWS)
	var fill: float = clampf(0.45 + 0.4 * L.p("size", 1.0), 0.4, 0.95)  # size 1.0 -> 85% blocks with gaps
	var block := cell * Vector2(fill, fill * 0.85)
	var base_y := area.end.y
	var calm: float = 1.0 - A.silence_amount * 0.5
	for c in cols:
		var x := area.position.x + c * cell.x + (cell.x - block.x) * 0.5
		var lit_f := height[c] * ROWS
		var lit: float = int(lit_f)
		# Soft column glow behind active blocks.
		if height[c] > 0.08:
			var top_y: float = base_y - height[c] * area.size.y
			Common.draw_soft(L, Vector2(x + block.x * 0.5, top_y + height[c] * area.size.y * 0.35), cell.x * (1.4 + height[c] * 2.0), Color(_gradient(height[c]), 0.12 * L.glow * calm))
		for r in ROWS:
			var f := float(r) / (ROWS - 1)
			var y := base_y - (r + 1) * cell.y + (cell.y - block.y)
			var rect := Rect2(Vector2(x, y), block)
			var col: Color = _gradient(f)
			if r < lit:
				_block(rect, col, 0.95 * calm)
				# Reflection: fainter as it goes down.
				var refl := Rect2(Vector2(x, base_y + (base_y - y) - block.y + cell.y * 0.3), block)
				if r < 6:
					_block(refl, col, 0.12 * (1.0 - r / 6.0) * calm, false)
			elif r == lit and lit_f - lit > 0.05:
				_block(rect, col, (0.2 + 0.75 * (lit_f - lit)) * calm)
			else:
				_block(rect, Color(col.darkened(0.75), 1.0), 0.35, false)
		# Peak cap: a thin glowing bar that holds, then falls.
		if peak[c] > 0.03:
			var py: float = base_y - peak[c] * area.size.y - 3.0
			var pc := _gradient(peak[c]).lightened(0.35)
			L.draw_rect(Rect2(Vector2(x, py), Vector2(block.x, maxf(block.y * 0.25, 2.0))), Color(pc, 0.95 * calm))
			Common.draw_soft(L, Vector2(x + block.x * 0.5, py), cell.x * 0.9, Color(pc, 0.3 * L.glow * calm))
