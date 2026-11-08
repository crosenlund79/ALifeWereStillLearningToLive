extends RefCounted
## SQUARE GRID — a lit field of tiles seen in gentle perspective.
##
## Columns run from bass (left) to treble (right). The front row shows the spectrum now;
## older rows recede toward the horizon, so the field flows away from you like a living
## landscape of sound. Each tile rises with its frequency's energy, with a lit top face,
## a shaded front face, depth fog and a soft glow on tall tiles. Beats send a ripple
## across the field. Colours run across the element palette from left to right.
## Settings: Grid density, Square size, Movement, Intensity, Glow, colours.

const Common := preload("res://vis/common.gd")

var L: Control
var A: Node
var cols := 0
var rows := 0
var history: Array[PackedFloat32Array] = []  # Row 0 = newest.
var timer := 0.0
var ripples: Array[Vector2] = []  # x = radius, y = strength
var t := 0.0
var poly := PackedVector2Array()
var poly_colors := PackedColorArray()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	poly.resize(4)
	poly_colors.resize(4)


func element_count() -> int:
	return cols * rows


func _ensure_size() -> void:
	var c := clampi(int(28 * L.p("density", 1.0)), 12, 56)
	var r := clampi(int(Common.pick(10, 14, 18) * clampf(L.p("density", 1.0), 0.7, 1.5)), 8, 24)
	if c == cols and r == rows:
		return
	cols = c
	rows = r
	history.clear()
	for i in rows:
		var row := PackedFloat32Array()
		row.resize(cols)
		history.append(row)


func update(delta: float) -> void:
	_ensure_size()
	t += delta
	# The front row follows the spectrum continuously; rows step back ~16 times a second.
	var levels: PackedFloat32Array = A.levels
	var per := float(levels.size()) / cols
	var front := history[0]
	for c in cols:
		var v := 0.0
		for i in range(int(c * per), int((c + 1) * per)):
			v = maxf(v, levels[i])
		front[c] = Common.approach(front[c], v, 14.0, delta)
	timer += delta
	if timer > 1.0 / 16.0:
		timer = 0.0
		var oldest: PackedFloat32Array = history.pop_back()
		for c in cols:
			oldest[c] = front[c]
		history.insert(1, oldest)
	if A.kick > 0.5 and (ripples.is_empty() or ripples[-1].x > 0.15) and ripples.size() < 4:
		ripples.append(Vector2(0.0, A.kick))
	var i := ripples.size() - 1
	while i >= 0:
		ripples[i].x += delta * 1.2
		if ripples[i].x > 1.6:
			ripples.remove_at(i)
		i -= 1


## World (x in -1..1, depth z in 0..1, height y) to screen.
func _project(x: float, z: float, y: float) -> Vector2:
	var s := 1.0 / (1.0 + z * 2.2)
	var w := L.size.x
	var h := L.size.y
	return Vector2(w * 0.5 + x * w * 0.46 * s, h * 0.36 + h * 0.54 * s - y * h * 0.22 * s)


func draw() -> void:
	if history.is_empty():
		return
	var fill: float = clampf(0.35 + 0.45 * L.p("size", 1.0), 0.3, 0.95)  # size 1.0 -> 80% tiles, visible gaps
	var move: float = L.p("range", 1.0) * L.intensity
	var calm: float = 1.0 - A.silence_amount * 0.6
	var hw := 1.0 / cols * fill
	var hd := 0.5 / rows * fill
	# Back to front so nearer tiles cover farther ones.
	for r in range(rows - 1, -1, -1):
		var z := (r + 0.5) / rows
		var fog: float = 1.0 - z * 0.75
		var row: PackedFloat32Array = history[r]
		for c in cols:
			var x := -1.0 + (c + 0.5) * 2.0 / cols
			var e: float = row[c]
			var ripple: float = 0.0
			for rp in ripples:
				var d := absf(Vector2(x * 0.8, z).length() - rp.x)
				if d < 0.12:
					ripple += rp.y * (1.0 - d / 0.12) * 0.35
			var height: float = (pow(e, 1.8) * 0.9 + ripple + 0.015) * move  # contrast: quiet tiles stay low
			var col: Color = _palette_at(float(c) / (cols - 1))
			var lit: float = clampf(0.15 + pow(e, 1.5) * 1.0 + ripple, 0.0, 1.2)
			# Top face.
			poly[0] = _project(x - hw, z - hd, height)
			poly[1] = _project(x + hw, z - hd, height)
			poly[2] = _project(x + hw, z + hd, height)
			poly[3] = _project(x - hw, z + hd, height)
			var top := col.darkened(0.55 * (1.0 - minf(lit, 1.0))).lightened(0.25 * maxf(lit - 0.6, 0.0))
			poly_colors[0] = Color(top, 0.95 * fog * calm)
			poly_colors[1] = poly_colors[0]
			poly_colors[2] = Color(top.darkened(0.25), 0.9 * fog * calm)
			poly_colors[3] = poly_colors[2]
			L.draw_polygon(poly, poly_colors)
			# Front face (only worth drawing when the tile stands up).
			if height > 0.03:
				poly[2] = _project(x + hw, z - hd, 0.0)
				poly[3] = _project(x - hw, z - hd, 0.0)
				var side := col.darkened(0.55)
				poly_colors[0] = Color(side.lightened(0.15 * lit), 0.9 * fog * calm)
				poly_colors[1] = poly_colors[0]
				poly_colors[2] = Color(side.darkened(0.5), 0.85 * fog * calm)
				poly_colors[3] = poly_colors[2]
				L.draw_polygon(poly, poly_colors)
			if lit > 0.55 and r < rows * 0.7:
				var top_center := _project(x, z, height)
				Common.draw_soft(L, top_center, L.size.y * 0.05 * (1.0 - z) * lit, Color(col, 0.22 * (lit - 0.45) * L.glow * fog))


func _palette_at(f: float) -> Color:
	var x := f * 6.0
	var i := mini(int(x), 5)
	return L.color(i).lerp(L.color(i + 1), x - i)
