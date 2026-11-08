extends RefCounted
## MULTI-WAVEFORM — one to seven glowing lines (replaces Waveform and Seven Waves).
##
## One line keeps the original golden waveform: the whole spectrum laid along the line,
## with warm hue drift from the analysis. With more lines, each follows its share of the
## seven EQ bands (60 Hz .. 15 kHz split evenly between the lines) and has its own colour.
## Settings: Lines, Line thickness, Movement (and the common Intensity, Glow, Speed).

const Common := preload("res://vis/common.gd")

var L: Control
var A: Node
var t := 0.0
var phase := PackedFloat32Array()
var line := PackedVector2Array()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	phase.resize(7)


func element_count() -> int:
	return clampi(int(L.p("count", 1)), 1, 7)


func update(delta: float) -> void:
	t += delta
	for i in 7:
		# Each line flows at its own pace; its band's energy speeds it up a little.
		phase[i] += delta * (0.9 + i * 0.15) * (0.8 + 0.6 * float(A.bands7[i]))


## Average energy of the bands assigned to line i of n.
func _energy(i: int, n: int) -> float:
	var b0 := int(floor(i * 7.0 / n))
	var b1 := maxi(int(floor((i + 1) * 7.0 / n)), b0 + 1)
	var e: float = 0.0
	for b in range(b0, b1):
		e += float(A.bands7[b])
	return e / (b1 - b0)


func draw() -> void:
	var n := clampi(int(L.p("count", 1)), 1, 7)
	var thick: float = L.p("thickness", 1.0)
	var move: float = L.p("range", 1.0) * L.intensity
	var w := L.size.x
	var h := L.size.y
	if n == 1:
		_draw_single(w, h, thick, move)
		return
	var points := Common.pick(80, 120, 170)
	if line.size() != points:
		line.resize(points)
	var spacing: float = h * 0.6 / n
	for i in n:
		var e: float = _energy(i, n)
		var base_y := h * 0.5 + (i - (n - 1) * 0.5) * spacing
		var amp := spacing * (0.06 + 0.55 * e) * move
		for j in points:
			var p := float(j) / (points - 1)
			var wave := sin(p * TAU * (1.5 + i * 0.35) + phase[i]) * 0.75 + sin(p * TAU * 4.1 - phase[i] * 1.3 + i) * 0.25
			line[j] = Vector2(p * w, base_y + wave * amp * sin(p * PI))
		_stroke(L.color(i), (0.08 + 0.3 * e + 0.12 * A.beat_light) * L.glow, thick)


## The original single golden line: the full spectrum along the line.
func _draw_single(w: float, h: float, thick: float, move: float) -> void:
	var levels: PackedFloat32Array = A.levels
	var n := levels.size()
	if line.size() != n:
		line.resize(n)
	var amp := h * 0.08 * move
	for i in n:
		var p := float(i) / (n - 1)
		var l := (levels[max(i - 1, 0)] + 2.0 * levels[i] + levels[min(i + 1, n - 1)]) * 0.25
		line[i] = Vector2(p * w, h * 0.5 + sin(p * TAU * 3.0 + t) * l * amp * sin(p * PI))
	# Warm hue drift: toward a deeper shade when instruments dominate the voice range.
	var col: Color = L.color(0).lerp(L.color(0).darkened(0.25).lerp(L.secondary, 0.3), (1.0 - A.tone) * 0.8)
	_stroke(col, (0.06 + A.loudness * 0.3 + A.beat_light * 0.15) * L.glow, thick)


func _stroke(col: Color, glow: float, thick: float) -> void:
	L.draw_polyline(line, Color(col, glow * 0.35), 14.0 * thick, true)
	L.draw_polyline(line, Color(col, glow * 0.6), 7.0 * thick, true)
	L.draw_polyline(line, Color(col, glow), 3.5 * thick, true)
	L.draw_polyline(line, Color(col.lightened(0.35), 0.95), 1.5 * maxf(thick, 0.6), true)
