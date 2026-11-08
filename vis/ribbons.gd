extends RefCounted
## HARMONIC RIBBONS — luminous ribbons twisting slowly through space.
##
## Each ribbon follows a 3D spine across the screen; its width vector rotates around the
## spine (the twist), and every quad is shaded by how much it faces the viewer, so the
## twists read as real surfaces with bright edges. Ribbons sit at different depths.
## Each ribbon follows its own share of the seven EQ bands: that band's energy widens it and
## brightens it; bass sways all ribbons, midrange drives the twisting, treble shimmers along
## the edges, and beats send a soft brightening along them.
## Settings: Ribbons, Ribbon width, Movement, Glow, Speed, colours.

const Common := preload("res://vis/common.gd")
const ROWS := 2

var L: Control
var A: Node
var samples := 0
var phase := PackedFloat32Array()
var twist := PackedFloat32Array()
var points := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var edge_a := PackedVector2Array()
var edge_b := PackedVector2Array()
var edge_cols := PackedColorArray()
var t := 0.0
var shimmer := 0.0


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	phase.resize(7)
	twist.resize(7)
	for i in 7:
		phase[i] = i * 1.9
		twist[i] = i * 0.7
	_allocate()


func element_count() -> int:
	return clampi(int(L.p("count", 4)), 1, 7) * samples


func _allocate() -> void:
	samples = Common.pick(60, 90, 130)
	points.resize(samples * ROWS)
	colors.resize(samples * ROWS)
	edge_a.resize(samples)
	edge_b.resize(samples)
	edge_cols.resize(samples)
	indices.clear()
	for s in samples - 1:
		indices.append_array([s, s + 1, samples + s + 1, s, samples + s + 1, samples + s])


func _energy(i: int, n: int) -> float:
	var b0 := int(floor(i * 7.0 / n))
	var b1 := maxi(int(floor((i + 1) * 7.0 / n)), b0 + 1)
	var e: float = 0.0
	for b in range(b0, b1):
		e += float(A.bands7[b])
	return e / (b1 - b0)


func update(delta: float) -> void:
	if samples != Common.pick(60, 90, 130):
		_allocate()
	t += delta
	shimmer = maxf(shimmer - delta * 3.0, A.beat_light)
	var move: float = L.p("range", 1.0)
	for i in 7:
		phase[i] += delta * (0.25 + 0.5 * A.low_mid + 0.3 * float(A.bands7[i])) * (0.8 + i * 0.07) * move
		twist[i] += delta * (0.2 + 0.9 * A.mid + 0.4 * float(A.bands7[i])) * (1.0 if i % 2 == 0 else -1.0)


func draw() -> void:
	var n := clampi(int(L.p("count", 4)), 1, 7)
	var w := L.size.x
	var h := L.size.y
	var ci := L.get_canvas_item()
	var move: float = L.p("range", 1.0) * L.intensity
	var width_mul: float = L.p("thickness", 1.0)
	var calm: float = 1.0 - A.silence_amount * 0.5
	var focal := h * 1.1
	# Far ribbons first.
	for k in n:
		var i := n - 1 - k
		var e: float = _energy(i, n)
		var depth := 2.4 + (float(i) / maxf(n - 1, 1) - 0.5) * 1.4  # ribbon distance
		var col: Color = L.color(i)
		var base_y := (float(i) - (n - 1) * 0.5) * 0.28
		var half_w: float = (0.05 + 0.10 * e) * width_mul
		var bright: float = clampf((0.18 + 0.5 * e + 0.25 * A.loudness + 0.2 * shimmer) * L.glow * calm, 0.0, 1.0)
		for s in samples:
			var u := float(s) / (samples - 1)
			var x := (u - 0.5) * 4.2
			var y: float = base_y + move * (0.22 * sin(u * 3.2 + phase[i]) + 0.10 * sin(u * 7.1 - phase[i] * 1.3) + 0.08 * A.bass * sin(u * 1.5 + t * 0.4))
			var z := depth + 0.5 * sin(u * 2.3 + phase[i] * 0.7)
			var ang := u * 4.0 + twist[i]
			var oy: float = cos(ang) * half_w
			var oz: float = sin(ang) * half_w
			var facing := absf(cos(ang))  # 1 = facing us, 0 = edge-on
			var s1 := focal / (z + oz)
			var s2 := focal / (z - oz)
			var p1 := Vector2(w * 0.5 + x * s1 * 0.5, h * 0.5 + (y + oy) * s1)
			var p2 := Vector2(w * 0.5 + x * s2 * 0.5, h * 0.5 + (y - oy) * s2)
			var fade := sin(u * PI)
			var shade := col.lightened(0.15 * (1.0 - facing)).darkened(0.35 * (1.0 - facing))
			var a: float = bright * fade * (0.35 + 0.65 * facing)
			points[s] = p1
			points[samples + s] = p2
			colors[s] = Color(shade, a)
			colors[samples + s] = Color(shade.darkened(0.15), a * 0.8)
			edge_a[s] = p1
			edge_b[s] = p2
			var glint: float = 0.6 + 0.4 * sin(u * 40.0 + t * 5.0) * A.treble
			edge_cols[s] = Color(col.lightened(0.5), clampf(bright * fade * (0.5 + 0.5 * (1.0 - facing)) * glint, 0.0, 1.0))
		RenderingServer.canvas_item_add_triangle_array(ci, indices, points, colors)
		L.draw_polyline_colors(edge_a, edge_cols, 1.4, true)
		L.draw_polyline_colors(edge_b, edge_cols, 1.4, true)
