extends RefCounted
## THE RESONANCE ENGINE — a kinetic sculpture of rings, arcs and fine lines.
##
## Inner rings answer to bass (core pulse, expansion), middle rings to midrange (rotation
## and contour distortion), outer rings and nodes to treble/air (fast detail). A radial
## waveform orbits between the layers. Percussive transients launch short shockwaves, and
## strong beats briefly pull every ring onto a common alignment before they drift apart
## again. Each ring has its own direction and inertia, so silence settles into a slow,
## elegant rotation rather than constant spinning.

const Common := preload("res://vis/common.gd")
const MAX_SHOCKS := 6

var L: Control
var A: Node
var rings := 0
var rot := PackedFloat32Array()
var omega := PackedFloat32Array()
var segs := PackedInt32Array()
var shocks: Array[Vector2] = []
var sync := 0.0
var core := 0.0
var t := 0.0
var cooldown := 0.0
var buf := PackedVector2Array()
var radial := PackedVector2Array()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	_allocate()


func _allocate() -> void:
	rings = Common.pick(5, 7, 9)
	rot.resize(rings)
	omega.resize(rings)
	segs.resize(rings)
	for i in rings:
		segs[i] = [3, 6, 8, 12, 16, 24, 32, 40, 48][i]
		rot[i] = i * 0.37
		omega[i] = 0.0
	buf.resize(14)
	radial.resize(Common.pick(96, 128, 192) + 1)


func element_count() -> int:
	var total := 0
	for s in segs:
		total += s
	return total


func update(delta: float) -> void:
	if rings != Common.pick(5, 7, 9):
		_allocate()
	t += delta
	cooldown -= delta
	core = Common.approach(core, A.bass * 0.8 + A.sub * 0.3 + A.kick * 0.6, 14.0 if A.bass > core else 4.0, delta)
	# Only clearly strong beats synchronise the layers.
	if A.beat > 0.9:
		sync = 1.0
	sync = maxf(sync - delta * 1.8, 0.0)
	if (A.kick > 0.5 or A.onset > 0.7) and cooldown <= 0.0 and shocks.size() < MAX_SHOCKS:
		shocks.append(Vector2(0.05, maxf(A.kick, A.onset)))
		cooldown = 0.16
	var i := shocks.size() - 1
	while i >= 0:
		shocks[i].x += delta * 0.95
		if shocks[i].x > 1.3:
			shocks.remove_at(i)
		i -= 1
	for r in rings:
		var f := float(r) / (rings - 1)
		var dir := 1.0 if r % 2 == 0 else -1.0
		var drive: float = (0.45 * A.mid + 0.2 * A.low_mid) * (1.0 - f) + (0.5 * A.treble + 0.3 * A.air) * f
		omega[r] = Common.approach(omega[r], dir * (0.035 + 0.05 * f + drive * (0.5 + f)), 2.0 + 2.0 * f, delta)
		rot[r] = wrapf(rot[r] + omega[r] * delta, -PI, PI)
		if sync > 0.0:
			var step := TAU / segs[r]
			rot[r] = lerp_angle(rot[r], round(rot[r] / step) * step, minf(sync * delta * 10.0, 1.0))


func draw() -> void:
	var center := L.size * 0.5
	var big := minf(L.size.x, L.size.y) * 0.44
	var calm: float = 1.0 - A.silence_amount * 0.5
	var glow: float = L.glow * calm

	# Core.
	var core_r := big * (0.07 + 0.06 * core)
	Common.draw_soft(L, center, core_r * 4.0, Color(L.primary, (0.25 + 0.4 * core) * glow))
	L.draw_arc(center, core_r, 0.0, TAU, 48, Color(L.primary.lightened(0.3), 0.7 * calm), 2.0, true)

	var prev_nodes: Array[Vector2] = []
	for r in rings:
		var f := float(r) / (rings - 1)
		var radius: float = big * (0.16 + 0.82 * f) * (1.0 + 0.07 * core * (1.0 - f)) * (0.85 + 0.15 * L.intensity)
		var distort: float = big * 0.025 * (A.mid * (1.0 - f * 0.5) + A.upper_mid * f) * L.intensity * L.p("range", 1.0)
		var col: Color = L.primary.lerp(L.secondary, f)
		var alpha: float = (0.3 + 0.35 * A.loudness + 0.25 * sync) * calm
		var width := 1.2 + 2.6 * (1.0 - f)
		var n := segs[r]
		var step := TAU / n
		var nodes: Array[Vector2] = []
		for s in n:
			var a0 := rot[r] + s * step
			var arc := step * (0.42 + 0.3 * sin(t * 0.2 + r + s * 0.5) * 0.5)
			for k in buf.size():
				var a := a0 + arc * float(k) / (buf.size() - 1)
				var rr := radius + distort * sin(a * 3.0 + t * 1.3 + r)
				buf[k] = center + Vector2(cos(a), sin(a)) * rr
			L.draw_polyline(buf, Color(col, alpha), width, true)
			nodes.append(buf[0])
			var node_glow: float = (0.25 + 0.6 * A.treble * f + 0.5 * A.snap * f) * glow
			Common.draw_soft(L, buf[0], (3.0 + 5.0 * A.air * f + 2.0 * (1.0 - f)) * L.size.y / 941.0 * 2.0, Color(col.lightened(0.4), node_glow))
		# Fine lines to the previous (inner) ring.
		if not prev_nodes.is_empty():
			var line_col := Color(col, (0.06 + 0.18 * A.treble + 0.1 * sync) * calm)
			for s in n:
				L.draw_line(nodes[s], prev_nodes[s * prev_nodes.size() / n], line_col, 1.0, true)
		prev_nodes = nodes
		# Radial waveform between the middle layers.
		if r == rings / 2:
			_draw_radial(center, radius * 0.86, big, col)

	for w in shocks:
		var fade := clampf(1.0 - w.x / 1.3, 0.0, 1.0)
		L.draw_arc(center, big * w.x * 1.1, 0.0, TAU, 96, Color(L.primary.lightened(0.4), w.y * fade * 0.6 * glow), 2.0 + 3.0 * fade, true)


func _draw_radial(center: Vector2, radius: float, big: float, col: Color) -> void:
	var levels: PackedFloat32Array = A.levels
	var count := radial.size() - 1
	for k in count + 1:
		var a := float(k) / count * TAU - PI * 0.5
		# Mirror the spectrum so the shape is symmetrical: low at the top, high at the bottom.
		var m := absf(float(k) / count * 2.0 - 1.0)
		var level := levels[int((1.0 - m) * (levels.size() - 1))]
		radial[k] = center + Vector2(cos(a), sin(a)) * (radius + level * big * 0.12 * L.intensity)
	L.draw_polyline(radial, Color(col.lightened(0.25), 0.55 * (1.0 - A.silence_amount * 0.5)), 1.4, true)
