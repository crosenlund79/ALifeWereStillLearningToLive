extends RefCounted
## THE PARTICLE UNIVERSE — a small living galaxy.
##
## Particles live on a tilted spiral disc and orbit with Kepler-like speeds. Bass expands
## the whole field through a spring (so it swells and settles), detected kicks launch
## ring waves that push particles outward as they pass, midrange speeds up the swirl,
## treble makes individual particles sparkle, and trails are short velocity streaks.
## All state lives in preallocated packed arrays; the count adapts to window size,
## quality preset and density.

const Common := preload("res://vis/common.gd")
const MAX_WAVES := 5

var L: Control
var A: Node
var n := 0
var ang := PackedFloat32Array()
var rad := PackedFloat32Array()
var disp := PackedFloat32Array()
var dvel := PackedFloat32Array()
var psize := PackedFloat32Array()
var twinkle := PackedFloat32Array()
var waves: Array[Vector2] = []  # x = radius (0..1.5), y = strength
var expand := 1.0
var expand_vel := 0.0
var swirl := 0.05
var t := 0.0
var kick_cooldown := 0.0
var rng := RandomNumberGenerator.new()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	rng.seed = 7


func element_count() -> int:
	return n


func _target_count() -> int:
	var area := clampf(L.size.x * L.size.y / (1920.0 * 1080.0), 0.45, 1.0)
	return int(Common.pick(260, 560, 1100) * area * clampf(L.density, 0.3, 1.6))


func _resize(count: int) -> void:
	var old := n
	n = count
	ang.resize(n)
	rad.resize(n)
	disp.resize(n)
	dvel.resize(n)
	psize.resize(n)
	twinkle.resize(n)
	for i in range(old, n):
		var r := pow(rng.randf(), 0.8)
		var arm := float(rng.randi_range(0, 2))
		ang[i] = arm * TAU / 3.0 + r * 2.8 + rng.randf_range(-0.22, 0.22) * (1.0 - r * 0.4) + rng.randf_range(-0.06, 0.06)
		rad[i] = 0.06 + r * 0.94
		disp[i] = 0.0
		dvel[i] = 0.0
		psize[i] = rng.randf_range(0.7, 1.8) * (1.3 - r * 0.5)
		twinkle[i] = rng.randf() * TAU


func update(delta: float) -> void:
	var target := _target_count()
	if absi(target - n) > n / 10 + 4:
		_resize(target)
	t += delta
	kick_cooldown -= delta

	# Field breathing: spring toward a bass-driven scale.
	var target_expand: float = 1.0 + 0.24 * A.bass + 0.12 * A.sub + 0.06 * A.loudness
	expand_vel += ((target_expand - expand) * 30.0 - expand_vel * 7.0) * delta
	expand += expand_vel * delta

	# Rhythmic impulses become outward travelling waves.
	if A.kick > 0.45 and kick_cooldown <= 0.0 and waves.size() < MAX_WAVES:
		waves.append(Vector2(0.0, A.kick))
		kick_cooldown = 0.18
	var i := waves.size() - 1
	while i >= 0:
		waves[i].x += delta * 1.15
		if waves[i].x > 1.5:
			waves.remove_at(i)
		i -= 1

	swirl = Common.approach(swirl, 0.05 + 0.45 * A.mid + 0.2 * A.low_mid + 0.1 * A.loudness, 3.0, delta)
	for p in n:
		ang[p] += delta * swirl * 0.55 / (rad[p] + 0.25)
		var push := 0.0
		for w in waves:
			var d := absf(rad[p] - w.x)
			if d < 0.09:
				push += w.y * (1.0 - d / 0.09)
		dvel[p] += (push * 2.2 - disp[p] * 38.0 - dvel[p] * 6.5) * delta
		disp[p] += dvel[p] * delta


func draw() -> void:
	var center := L.size * 0.5
	var r_px := minf(L.size.x, L.size.y) * 0.47
	var stretch := clampf(L.size.x / L.size.y, 1.0, 1.9) * 0.85
	var px_scale := L.size.y / 941.0
	var calm: float = 1.0 - A.silence_amount * 0.5
	Common.draw_soft(L, center, r_px * 0.45 * expand, Color(L.primary, (0.10 + 0.22 * A.bass + 0.1 * A.beat_light) * L.glow * calm))
	var sparkle: float = A.treble * 0.9 + A.snap * 0.6
	var trail: float = L.trail
	for p in n:
		var a := ang[p]
		var r := rad[p] * expand + disp[p]
		var dir := Vector2(cos(a) * stretch, sin(a) * 0.58)
		var pos := center + dir * r * r_px
		var tw := pow(maxf(sin(twinkle[p] + t * 2.7), 0.0), 10.0) * sparkle
		var bright: float = (0.4 + 0.5 * (1.0 - rad[p]) + 0.35 * A.loudness + tw) * calm
		var col: Color = L.primary.lerp(L.secondary, rad[p])
		var sz: float = psize[p] * (2.0 + 1.6 * (1.0 - rad[p]) + 0.5 * A.beat) * px_scale
		if trail > 0.05:
			var tangent := Vector2(-sin(a) * stretch, cos(a) * 0.58)
			var v := tangent * swirl * 0.55 / (rad[p] + 0.25) * r * r_px + dir * dvel[p] * r_px
			L.draw_line(pos, pos - v * trail * 0.06, Color(col, bright * 0.28 * L.glow), 1.0)
		Common.draw_soft(L, pos, sz * 2.6, Color(col.lightened(tw * 0.5), clampf(bright * L.glow, 0.0, 1.0)))
