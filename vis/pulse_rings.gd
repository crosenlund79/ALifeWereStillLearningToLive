extends RefCounted
## PULSE RINGS — concentric luminous rings, layered in gentle perspective.
##
## Inner rings answer to bass, middle rings to the mids, outer rings to the treble (each
## follows its own EQ band). A ring breathes outward with its band, its outline ripples with
## a soft polar distortion, and it glows in three layered strokes. When a ring's band jumps
## (or on a strong beat) it releases a fading echo that drifts outward. The ring stack is
## tilted and offset so the rings read as layers in depth. Echo brightness is capped and
## spawning is rate-limited, so fast percussion never strobes.
## Settings: Rings, Thickness, Responsiveness, Glow, colours.

const Common := preload("res://vis/common.gd")
const MAX_ECHOES := 12

var L: Control
var A: Node
var level := PackedFloat32Array()
var prev := PackedFloat32Array()
var echoes: Array[Vector4] = []  # x = ring, y = extra radius, z = strength, w = age
var cooldown := PackedFloat32Array()
var buf := PackedVector2Array()
var t := 0.0
var tilt := 0.0


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	level.resize(9)
	prev.resize(9)
	cooldown.resize(9)


func element_count() -> int:
	return clampi(int(L.p("count", 6)), 2, 9) + echoes.size()


func _band_for(i: int, n: int) -> float:
	var b := clampi(int(round(float(i) / maxf(n - 1, 1) * 6.0)), 0, 6)
	return float(A.bands7[b])


func update(delta: float) -> void:
	t += delta
	var n := clampi(int(L.p("count", 6)), 2, 9)
	var resp: float = L.p("response", 1.0)
	tilt = Common.approach(tilt, 0.25 + 0.15 * sin(t * 0.11), 1.0, delta)
	for i in n:
		var e: float = _band_for(i, n) * resp
		level[i] = Common.approach(level[i], e, 12.0 if e > level[i] else 3.0, delta)
		cooldown[i] -= delta
		var jump: float = e - prev[i]
		prev[i] = e
		if (jump > 0.18 or A.beat > 0.9) and cooldown[i] <= 0.0 and echoes.size() < MAX_ECHOES:
			echoes.append(Vector4(i, 0.0, clampf(e, 0.3, 1.0), 0.0))
			cooldown[i] = 0.35
	var k := echoes.size() - 1
	while k >= 0:
		var ec := echoes[k]
		ec.y += delta * (0.08 + 0.1 * ec.z)
		ec.w += delta
		echoes[k] = ec
		if ec.w > 1.6:
			echoes.remove_at(k)
		k -= 1


func _ring(center: Vector2, radius: float, squash: float, distort: float, phase: float, col: Color, alpha: float, thick: float) -> void:
	var count := Common.pick(72, 110, 160)
	if buf.size() != count + 1:
		buf.resize(count + 1)
	for j in count + 1:
		var a: float = float(j) / count * TAU
		var r := radius * (1.0 + distort * (0.6 * sin(a * 3.0 + phase) + 0.4 * sin(a * 5.0 - phase * 1.3)))
		buf[j] = center + Vector2(cos(a) * r, sin(a) * r * squash)
	L.draw_polyline(buf, Color(col, alpha * 0.18), thick * 7.0, true)
	L.draw_polyline(buf, Color(col, alpha * 0.4), thick * 3.0, true)
	L.draw_polyline(buf, Color(col.lightened(0.35), alpha), maxf(thick * 1.2, 1.0), true)


func draw() -> void:
	var n := clampi(int(L.p("count", 6)), 2, 9)
	var thick: float = L.p("thickness", 1.0) * L.size.y / 941.0 * 1.6
	var big := minf(L.size.x, L.size.y) * 0.46
	var calm: float = 1.0 - A.silence_amount * 0.55
	var glow: float = L.glow * calm
	var squash := 1.0 - tilt
	Common.draw_soft(L, L.size * 0.5, big * (0.5 + 0.3 * A.bass), Color(L.color(0), 0.10 * glow))
	# Outer rings first; each ring sits a little lower, as if stacked in depth.
	for k in n:
		var i := n - 1 - k
		var f := float(i) / (n - 1)
		var e: float = level[i]
		var center := L.size * 0.5 + Vector2(0, (f - 0.5) * big * 0.12 * tilt * 2.0)
		var radius: float = big * (0.14 + 0.82 * f) * (1.0 + 0.10 * e * L.intensity)
		var distort: float = (0.015 + 0.05 * A.mid * (1.0 - f) + 0.04 * A.treble * f) * L.intensity
		var alpha: float = clampf((0.3 + 0.6 * e) * glow, 0.0, 1.0)
		_ring(center, radius, squash, distort, t * (0.6 + f), L.color(i), alpha, thick * (1.2 - 0.5 * f))
	for ec in echoes:
		var i := int(ec.x)
		var f := float(i) / (n - 1)
		var fade := clampf(1.0 - ec.w / 1.6, 0.0, 1.0)
		var center := L.size * 0.5 + Vector2(0, (f - 0.5) * big * 0.12 * tilt * 2.0)
		var radius: float = big * (0.14 + 0.82 * f + ec.y)
		_ring(center, radius, squash, 0.01, t, L.color(i), minf(ec.z * fade * fade * 0.5, 0.5) * glow, thick * 0.8)
