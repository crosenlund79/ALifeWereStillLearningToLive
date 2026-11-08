extends RefCounted
## THE SEVEN SPIRITS — seven luminous entities, one per EQ band (60 Hz .. 15 kHz).
##
## Every spirit is a damped spring chasing a target made of:
##  - a formation anchor: a slowly turning ring that tightens in quiet passages and opens
##    with sustained energy, blending into a loose arc when the music is full;
##  - a personal wander (its own Lissajous frequencies) scaled by its band's sustained level;
##  - a pair orbit, so neighbours circle one another.
## Transients answer per register: low spirits are knocked outward by kicks, the vocal-range
## spirit by onsets, high spirits get quick sideways flicks from sharp treble. Strong beats
## briefly align their wander phases; they then drift back to independent motion.
## Heavier (lower) spirits have more inertia. Trails are fixed-size ring buffers.

const Common := preload("res://vis/common.gd")
# mass, wander x, wander y, freq x, freq y, orbit direction
const PERSONA := [
	[2.6, 0.11, 0.06, 0.13, 0.21, 1.0],
	[2.1, 0.09, 0.08, 0.17, 0.11, -1.0],
	[1.6, 0.08, 0.09, 0.23, 0.19, 1.0],
	[1.25, 0.10, 0.07, 0.29, 0.37, -1.0],
	[1.0, 0.07, 0.10, 0.41, 0.27, 1.0],
	[0.8, 0.06, 0.08, 0.53, 0.47, -1.0],
	[0.6, 0.05, 0.06, 0.71, 0.61, 1.0],
]

var L: Control
var A: Node
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var ph_x := PackedFloat32Array()
var ph_y := PackedFloat32Array()
var flash := PackedFloat32Array()
var trails: Array[PackedVector2Array] = []
var trail_len := 0
var trail_head := 0
var trail_timer := 0.0
var form_rot := 0.0
var spread := 0.4
var line_amount := 0.0
var sync := 0.0
var common_phase := 0.0
var pair_rot := 0.0
var t := 0.0


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	pos.resize(7)
	vel.resize(7)
	ph_x.resize(7)
	ph_y.resize(7)
	flash.resize(7)
	for i in 7:
		var a: float = i * TAU / 7.0
		pos[i] = Vector2(cos(a), sin(a)) * 0.15
		ph_x[i] = i * 1.3
		ph_y[i] = i * 2.1
	_allocate_trails()


func _allocate_trails() -> void:
	trail_len = Common.pick(14, 24, 36)
	trails.clear()
	for i in 7:
		var tr := PackedVector2Array()
		tr.resize(trail_len)
		tr.fill(pos[i])
		trails.append(tr)
	trail_head = 0


func element_count() -> int:
	return 7 * (1 + trail_len)


func update(delta: float) -> void:
	if trail_len != Common.pick(14, 24, 36):
		_allocate_trails()
	t += delta
	var aspect := clampf(L.size.x / maxf(L.size.y, 1.0), 1.0, 1.9)

	var spread_target: float = 0.30 + 0.70 * A.energy_slow + 0.25 * A.loudness + 0.25 * maxf(A.energy_delta, 0.0)
	spread = Common.approach(spread, clampf(spread_target, 0.25, 1.15), 0.9, delta)
	line_amount = Common.approach(line_amount, 1.0 if A.energy_slow > 0.62 else 0.0, 0.25, delta)
	form_rot += delta * (0.04 + 0.22 * A.mid + 0.08 * A.loudness)
	pair_rot += delta * (0.35 + 0.9 * A.mid)
	if A.beat > 0.85:
		sync = 1.0
		common_phase = ph_x[3]
	sync = maxf(sync - delta * 1.2, 0.0)
	common_phase += delta * 0.6

	# Customization: Spacing, Movement range, Responsiveness (1.0 = the original behaviour).
	var spacing: float = L.p("spacing", 1.0)
	var move_range: float = L.p("range", 1.0)
	var response: float = L.p("response", 1.0)
	for i in 7:
		var p: Array = PERSONA[i]
		var e: float = A.bands7[i]
		ph_x[i] += delta * p[3] * (2.0 + 3.0 * e) * TAU * 0.25
		ph_y[i] += delta * p[4] * (2.0 + 3.0 * e) * TAU * 0.25
		var px: float = lerpf(ph_x[i], common_phase, sync)
		var py: float = lerpf(ph_y[i], common_phase * 1.3, sync)

		var a: float = form_rot + i * TAU / 7.0
		var ring := Vector2(cos(a) * 0.36 * aspect * 0.62, sin(a) * 0.24) * spread
		var arc := Vector2((i - 3) / 3.0 * 0.40 * aspect * 0.62, sin(i * 0.9 + t * 0.2) * 0.07 - 0.02) * (0.6 + 0.5 * spread)
		var anchor: Vector2 = ring.lerp(arc, line_amount) * spacing
		var wander := Vector2(sin(px) * p[1], sin(py) * p[2]) * (0.45 + 1.3 * e) * (0.6 + 0.5 * spread) * move_range
		var pair := Vector2.ZERO
		if i < 6:
			var side := 1.0 if i % 2 == 0 else -1.0
			pair = Vector2(cos(pair_rot * p[5]), sin(pair_rot * p[5])) * 0.035 * (0.5 + e) * side
		var target := anchor + wander + pair

		var mass: float = p[0]
		var k: float = 7.0 / mass * (0.6 + 0.4 * response)
		var c := 2.0 * sqrt(k) * 0.5
		var acc: Vector2 = (target - pos[i]) * k - vel[i] * c
		# Register-specific transient response.
		var out_dir := pos[i].normalized() if pos[i].length() > 0.001 else Vector2.RIGHT
		var hit := 0.0
		if i <= 2:
			hit = A.kick
			acc += out_dir * A.kick * 3.2 / mass * response
		elif i == 3:
			hit = A.onset
			acc += out_dir * A.onset * 2.0 / mass * response
		else:
			hit = A.snap
			acc += out_dir.orthogonal() * A.snap * 2.4 / mass * (1.0 if i % 2 == 0 else -1.0) * response
		flash[i] = maxf(flash[i] - delta * 3.0, hit)
		vel[i] += acc * delta
		pos[i] += vel[i] * delta
		# Soft walls keep them on screen at any aspect ratio.
		var lim := Vector2(0.5 * aspect - 0.07, 0.43)
		if absf(pos[i].x) > lim.x:
			vel[i].x -= signf(pos[i].x) * (absf(pos[i].x) - lim.x) * 30.0 * delta
		if absf(pos[i].y) > lim.y:
			vel[i].y -= signf(pos[i].y) * (absf(pos[i].y) - lim.y) * 30.0 * delta

	trail_timer += delta
	if trail_timer >= 1.0 / 30.0:
		trail_timer = 0.0
		trail_head = (trail_head + 1) % trail_len
		for i in 7:
			trails[i][trail_head] = pos[i]


func light_sources() -> Array:
	var out: Array = []
	var unit := L.size.y
	for i in 7:
		var e: float = A.bands7[i]
		out.append([L.size * 0.5 + pos[i] * unit, Color(L.color(i), (0.45 + 0.7 * e + 0.4 * flash[i]) * L.p("size", 1.0))])
	return out


func draw() -> void:
	var unit := L.size.y
	var center := L.size * 0.5
	var calm: float = 1.0 - A.silence_amount * 0.45
	var glow: float = L.glow * calm
	var length := int(trail_len * clampf(0.25 + L.trail, 0.25, 1.0))
	var sz: float = L.p("size", 1.0)
	for i in 7:
		var e: float = A.bands7[i]
		var col: Color = L.color(i)  # Each spirit has its own colour (element palette).
		# Trail: oldest -> newest, thickening and brightening toward the spirit.
		var prev := center + trails[i][(trail_head - length + 1 + trail_len) % trail_len] * unit
		for k in range(1, length):
			var idx := (trail_head - length + 1 + k + trail_len) % trail_len
			var p := center + trails[i][idx] * unit
			var f := float(k) / length
			L.draw_line(prev, p, Color(col, f * f * 0.32 * glow), (0.8 + 3.2 * f) * unit / 941.0, true)
			prev = p
		var at := center + pos[i] * unit
		var halo: float = unit * (0.07 + 0.09 * e) * (1.0 + flash[i] * 0.35) * (0.8 + 0.2 * L.intensity) * sz
		Common.draw_soft(L, at, halo, Color(col, (0.3 + 0.5 * e + 0.25 * flash[i]) * glow))
		Common.draw_soft(L, at, unit * (0.026 + 0.016 * e + 0.014 * flash[i]) * sz, Color(col.lightened(0.5), 0.95 * calm))
		L.draw_circle(at, unit * 0.0045 * sz, Color(1, 1, 1, 0.85 * calm))
