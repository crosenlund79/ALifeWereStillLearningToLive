extends RefCounted
## Atmospheric layers and the shared beat light.
##  - "glow": broad soft light pools that breathe with bass and swell on crescendos.
##  - "dust": sparse motes drifting upward; treble makes them glint.
##  - "beatlight": a restrained radial flash on detected beats. Uses the audio service's
##    rate-limited `beat_light`, so fast percussion gives gentler pulses, never a strobe.

const Common := preload("res://vis/common.gd")

var L: Control
var A: Node
var mode: String
var t := 0.0
var motes := PackedVector3Array()  # x, y (0..1), phase
var rng := RandomNumberGenerator.new()
var swell := 0.0


func _init(layer: Control, m: String) -> void:
	L = layer
	A = layer.audio
	mode = m
	rng.seed = 11
	if mode == "dust":
		motes.resize(Common.pick(50, 90, 150))
		for i in motes.size():
			motes[i] = Vector3(rng.randf(), rng.randf(), rng.randf() * TAU)


func element_count() -> int:
	return motes.size()


func update(delta: float) -> void:
	t += delta
	swell = Common.approach(swell, A.loudness * 0.6 + maxf(A.energy_delta, 0.0) * 1.2 + A.bass * 0.3, 2.0, delta)
	if mode == "dust":
		var lift: float = 0.004 + 0.02 * A.loudness
		for i in motes.size():
			var m := motes[i]
			m.y -= delta * lift * (0.6 + 0.4 * sin(m.z))
			m.x += delta * 0.004 * sin(t * 0.3 + m.z)
			if m.y < -0.02:
				m.y = 1.02
				m.x = rng.randf()
			motes[i] = m


func draw() -> void:
	var w := L.size.x
	var h := L.size.y
	var calm: float = 1.0 - A.silence_amount * 0.6
	match mode:
		"glow":
			for k in 3:
				var x := w * (0.25 + 0.25 * k) + sin(t * 0.07 + k * 2.0) * w * 0.05
				var c: Color = L.primary.lerp(L.secondary, k / 2.0)
				Common.draw_soft(L, Vector2(x, h * (0.62 + 0.05 * sin(t * 0.05 + k))), h * (0.35 + 0.12 * swell), Color(c, (0.06 + 0.14 * swell) * L.glow * calm))
		"dust":
			var size_px := h / 941.0
			for m in motes:
				var glint: float = pow(maxf(sin(m.z * 3.0 + t * 1.7), 0.0), 8.0) * (A.treble + A.air * 0.5)
				var a: float = (0.15 + 0.25 * A.loudness + glint * 0.8) * L.glow * calm
				Common.draw_soft(L, Vector2(m.x * w, m.y * h), (2.5 + 3.0 * glint) * size_px * 2.0, Color(L.primary.lightened(0.3), clampf(a, 0.0, 0.9)))
		"beatlight":
			var flash: float = A.beat_light * L.intensity
			if flash > 0.01:
				var c := Vector2(w, h) * 0.5
				Common.draw_soft(L, c, maxf(w, h) * (0.55 + 0.1 * flash), Color(L.primary, clampf(flash * 0.22, 0.0, 0.25)))
