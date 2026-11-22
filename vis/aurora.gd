extends RefCounted
## THE AURORA — luminous ribbon curtains made of sound.
##
## Each ribbon is a strip mesh (4 rows x N samples) with per-vertex colour, drawn with one
## triangle-array call: a soft lower fade, a bright lower edge and a tall curtain fading
## upward. Bass drives broad sway and depth, midrange shapes the flowing contours and
## curtain height, treble adds fine ripples along the upper edge, and transients light up
## the lower edges. Motion advances on audio-weighted time, so quiet passages breathe slowly.

const Common := preload("res://vis/common.gd")
const ROWS := 4

var L: Control
var A: Node
var ribbons := 0
var samples := 0
var phase := PackedFloat32Array()
var sway := PackedFloat32Array()
var points := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var edge := PackedVector2Array()
var edge_colors := PackedColorArray()
var t := 0.0
var flare := 0.0


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	_allocate()


func _allocate() -> void:
	ribbons = Common.pick(3, 4, 6)
	samples = Common.pick(48, 72, 112)
	phase.resize(ribbons)
	sway.resize(ribbons)
	for i in ribbons:
		phase[i] = i * 1.7
		sway[i] = i * 0.9
	points.resize(ROWS * samples)
	colors.resize(ROWS * samples)
	edge.resize(samples)
	edge_colors.resize(samples)
	indices.clear()
	for r in ROWS - 1:
		for s in samples - 1:
			var a: float = r * samples + s
			var b := a + 1
			var c := a + samples + 1
			var d := a + samples
			indices.append_array([a, b, c, a, c, d])


func element_count() -> int:
	return ribbons * samples


func update(delta: float) -> void:
	if samples != Common.pick(48, 72, 112):
		_allocate()
	t += delta
	flare = maxf(flare - delta * 2.5, maxf(A.onset, A.beat_light * 0.8))
	for i in ribbons:
		var depth := float(i) / maxf(ribbons - 1, 1)
		phase[i] += delta * (0.10 + 0.55 * A.mid + 0.25 * A.low_mid + 0.1 * A.loudness) * (0.7 + 0.6 * depth)
		sway[i] += delta * (0.04 + 0.35 * A.bass + 0.15 * A.sub)


func draw() -> void:
	var w := L.size.x
	var h := L.size.y
	var ci := L.get_canvas_item()
	var calm: float = 1.0 - A.silence_amount * 0.6
	for i in ribbons:
		var depth := float(i) / maxf(ribbons - 1, 1)  # 0 = far, 1 = near
		var base_y := h * (0.30 + 0.24 * depth)
		var move: float = L.p("range", 1.0)  # Movement strength (1.0 = original)
		var contour: float = h * (0.05 + 0.10 * A.mid + 0.04 * A.low_mid) * (0.6 + 0.6 * depth) * move
		var broad: float = h * (0.03 + 0.07 * A.bass + 0.03 * A.sub) * move
		var height: float = h * (0.10 + 0.20 * A.mid + 0.10 * A.bass + 0.08 * A.energy_slow) * (0.65 + 0.45 * depth) * L.intensity
		var ripple: float = h * (0.004 + 0.014 * A.treble + 0.008 * A.air)
		var alpha: float = clampf((0.16 + 0.34 * A.loudness + 0.25 * flare) * (0.45 + 0.55 * depth) * L.glow * calm, 0.0, 0.85)
		for s in samples:
			var p := float(s) / (samples - 1)
			var x := p * w
			var y := base_y \
				+ contour * (sin(p * 4.6 + phase[i]) * 0.65 + sin(p * 9.3 - phase[i] * 1.4 + i) * 0.35) \
				+ broad * sin(p * 1.8 + sway[i])
			var fold := 0.55 + 0.45 * sin(p * 7.0 + phase[i] * 0.8 + i * 2.3)
			var top := y - height * fold + ripple * (sin(p * 70.0 + t * 7.0 + i) + 0.6 * sin(p * 31.0 - t * 4.3))
			var mixf := 0.5 + 0.5 * sin(p * 3.1 + t * 0.12 + i * 1.3)
			var col: Color = L.primary.lerp(L.secondary, mixf)
			var edge_glow: float = alpha * (1.0 + 0.6 * A.upper_mid)
			points[s] = Vector2(x, y + h * 0.025)
			colors[s] = Color(col, 0.0)
			points[samples + s] = Vector2(x, y)
			colors[samples + s] = Color(col.lightened(0.15), edge_glow)
			points[2 * samples + s] = Vector2(x, lerpf(y, top, 0.3))
			var ray := 0.7 + 0.3 * sin(p * 140.0 + phase[i] * 0.6 + i * 3.0) * sin(p * 37.0 - t * 0.3)
			colors[2 * samples + s] = Color(col, alpha * 0.55 * ray)
			points[3 * samples + s] = Vector2(x, top)
			colors[3 * samples + s] = Color(col.lerp(L.secondary, 0.4), 0.0)
			edge[s] = Vector2(x, y)
			edge_colors[s] = Color(col.lightened(0.5), clampf(flare * 0.7 * (0.4 + 0.6 * depth) * L.glow, 0.0, 0.9))
		RenderingServer.canvas_item_add_triangle_array(ci, indices, points, colors)
		if flare > 0.05:
			L.draw_polyline_colors(edge, edge_colors, 1.6 + 1.2 * depth, true)
