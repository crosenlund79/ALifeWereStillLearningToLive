extends RefCounted
## THE PARTICLE UNIVERSE — a living volume of light, seen through a slowly moving camera.
##
## Particles live in 3D in three depth shells (foreground, middle, background). A camera
## orbits gently and sways (plus a little mouse parallax), and everything is projected with
## perspective: near particles are larger, faster on screen and out of focus (soft bokeh),
## far ones small, slow and faint in depth fog. Motion follows a smooth flow field that the
## midrange stirs; bass breathes the whole volume outward; kicks send spherical shockwaves
## through it; treble makes particles glint; loudness raises luminosity. Trails are short
## motion streaks. All state is in preallocated packed arrays.
## Settings: Density, Particle size, Depth, Movement, Trails, colours.

const Common := preload("res://vis/common.gd")
const MAX_WAVES := 4
const FOCUS := 5.0  # Distance of the sharpest plane.
const CAMERA := 5.5  # Camera distance from the centre of the volume.

var L: Control
var A: Node
var n := 0
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
var pseed := PackedFloat32Array()
var psize := PackedFloat32Array()
var tint := PackedInt32Array()
var screen_prev := PackedVector2Array()
var waves: Array[Vector2] = []  # x = radius, y = strength
var breath := 0.0
var flow := 0.1
var yaw := 0.0
var pitch := 0.0
var t := 0.0
var cooldown := 0.0
var parallax := Vector2.ZERO
var rng := RandomNumberGenerator.new()


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	rng.seed = 7


func element_count() -> int:
	return n


func _target_count() -> int:
	var area := clampf(L.size.x * L.size.y / (1920.0 * 1080.0), 0.45, 1.0)
	return int(Common.pick(300, 600, 1100) * area * clampf(L.density * L.p("density", 1.0), 0.3, 2.0))


func _spawn(i: int) -> void:
	# Three shells: 20% foreground, 45% middle, 35% background, spread around the axis.
	var shell := rng.randf()
	var r := 0.3 + rng.randf() * 0.7 if shell < 0.2 else (0.9 + rng.randf() * 0.9 if shell < 0.65 else 1.8 + rng.randf() * 1.2)
	var a: float = rng.randf() * TAU
	var y := rng.randf_range(-1.0, 1.0) * (0.35 + r * 0.25)
	px[i] = cos(a) * r
	py[i] = y
	pz[i] = sin(a) * r
	pseed[i] = rng.randf() * 100.0
	psize[i] = rng.randf_range(0.6, 1.6)
	tint[i] = rng.randi_range(0, 6)


func _resize(count: int) -> void:
	var old := n
	n = count
	px.resize(n)
	py.resize(n)
	pz.resize(n)
	pseed.resize(n)
	psize.resize(n)
	tint.resize(n)
	screen_prev.resize(n)
	for i in range(old, n):
		_spawn(i)
		screen_prev[i] = Vector2(-1, -1)


func update(delta: float) -> void:
	var target := _target_count()
	if absi(target - n) > n / 10 + 4:
		_resize(target)
	t += delta
	cooldown -= delta
	var move: float = L.p("range", 1.0)
	breath = Common.approach(breath, A.bass * 0.35 + A.sub * 0.15 + A.loudness * 0.08, 6.0 if A.bass > breath else 2.0, delta)
	flow = Common.approach(flow, (0.08 + 0.5 * A.mid + 0.2 * A.low_mid + 0.15 * A.loudness) * move, 2.5, delta)
	# Camera: slow orbit and sway, a little faster when the music swells.
	yaw += delta * (0.05 + 0.08 * A.energy_slow) * move
	pitch = sin(t * 0.07) * 0.18
	var mouse := L.get_local_mouse_position() / L.size - Vector2(0.5, 0.5) if L.size.x > 0.0 else Vector2.ZERO
	parallax = parallax.lerp(mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * 0.25, 1.0 - exp(-2.0 * delta))

	if A.kick > 0.5 and cooldown <= 0.0 and waves.size() < MAX_WAVES:
		waves.append(Vector2(0.1, A.kick))
		cooldown = 0.2
	var w := waves.size() - 1
	while w >= 0:
		waves[w].x += delta * 2.2
		if waves[w].x > 4.0:
			waves.remove_at(w)
		w -= 1

	for i in n:
		var x := px[i]
		var y := py[i]
		var z := pz[i]
		var s := pseed[i]
		# Smooth flow field (cheap curl-like noise from layered sines) plus a gentle swirl.
		var vx := sin(y * 1.7 + t * 0.21 + s) + 0.6 * sin(z * 1.3 - t * 0.17)
		var vy := sin(z * 1.5 + t * 0.19 + s * 1.3) * 0.6
		var vz := sin(x * 1.6 - t * 0.23 + s * 0.7) + 0.6 * cos(y * 1.2 + t * 0.15)
		vx += -z * 0.35
		vz += x * 0.35
		var radial := Vector3(x, y * 0.5, z).normalized()
		var push := 0.0
		var dist := Vector3(x, y, z).length()
		for wv in waves:
			var d := absf(dist - wv.x)
			if d < 0.35:
				push += wv.y * (1.0 - d / 0.35)
		x += (vx * flow + radial.x * push * 1.6) * delta * 0.5
		y += (vy * flow + radial.y * push * 1.6) * delta * 0.5
		z += (vz * flow + radial.z * push * 1.6) * delta * 0.5
		# Soft containment: drift back toward the volume.
		var r := Vector2(x, z).length()
		if r > 3.2 or absf(y) > 1.5:
			_spawn(i)
			screen_prev[i] = Vector2(-1, -1)
			continue
		px[i] = x
		py[i] = y
		pz[i] = z


func draw() -> void:
	var size := L.size
	var center := size * 0.5
	var focal := minf(size.x, size.y) * 0.8
	var depth_amount: float = L.p("depth", 1.0)
	var size_mul: float = L.p("size", 1.0)
	var calm: float = 1.0 - A.silence_amount * 0.5
	var lum: float = (0.6 + 0.4 * A.loudness + 0.15 * A.beat_light) * calm * L.glow
	var expand := 1.0 + breath * 0.4
	var cy := cos(yaw + parallax.x)
	var sy := sin(yaw + parallax.x)
	var cp := cos(pitch + parallax.y)
	var sp := sin(pitch + parallax.y)
	var sparkle: float = A.treble + A.snap * 0.6
	var trail: float = L.trail
	var px_unit := size.y / 941.0
	# Gentle core glow in the middle of the volume.
	Common.draw_soft(L, center, size.y * (0.35 + 0.15 * breath), Color(L.primary, 0.08 * lum))
	for i in n:
		# Camera transform: yaw around Y, then pitch around X, camera 3.6 units back.
		var x := px[i] * expand
		var y := py[i] * expand
		var z := pz[i] * expand
		var xr := x * cy - z * sy
		var zr := x * sy + z * cy
		var yr := y * cp - zr * sp
		zr = y * sp + zr * cp
		var cam_z: float = zr + CAMERA
		if cam_z < 0.3:
			screen_prev[i] = Vector2(-1, -1)
			continue
		var scr: Vector2 = center + Vector2(xr, yr) * focal / cam_z
		# Depth of field: blur grows away from the focus plane.
		# Depth cues: near = bigger, out of focus (bokeh); far = smaller, fainter in fog.
		var blur: float = clampf(absf(cam_z - FOCUS) * 0.35 * depth_amount, 0.0, 1.8)
		var near: float = clampf(FOCUS / cam_z, 0.35, 2.5)
		var fog: float = clampf(1.25 - (cam_z - 2.5) * 0.12 * depth_amount, 0.3, 1.0)
		var radius: float = psize[i] * near * (3.5 + blur * 6.0) * px_unit * size_mul
		var glint: float = pow(maxf(sin(pseed[i] * 7.0 + t * 2.4), 0.0), 12.0) * sparkle
		var alpha: float = clampf(lum * fog * 1.4 / (1.0 + blur * 1.2) + glint * 0.6 * fog, 0.0, 1.0)
		var col: Color = L.color(tint[i]).lerp(L.primary, 0.35).lightened(glint * 0.4)
		if trail > 0.05 and screen_prev[i].x >= 0.0:
			var dv: Vector2 = scr - screen_prev[i]
			if dv.length() < size.y * 0.2:
				L.draw_line(scr, scr - dv * trail * 6.0, Color(col, alpha * 0.25), maxf(radius * 0.25, 1.0))
		screen_prev[i] = scr
		Common.draw_soft(L, scr, radius, Color(col, alpha))
