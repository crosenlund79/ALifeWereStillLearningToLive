extends Node2D
## Built-in dancing companions, drawn procedurally in a 256x512 transparent SubViewport
## (so the same lighting shader works for them and for sprite dancers).
##  - "Lumen": a slender figure with a flowing scarf. Hips sway with bass, arms with mids,
##    steps land on beats, arms rise as the music swells.
##  - "Pip": a round little creature that hops and squashes on beats, with a swinging
##    antenna that sparkles with treble.
## Motion uses the shared audio analysis only (no extra analysis).

const W := 256.0
const H := 512.0

var character := "Lumen"
var t := 0.0
var phase := 0.0
var hop := 0.0
var sway := 0.0
var lift := 0.0
var arm := 0.0
var spark := 0.0
var step_side := 1.0


func update_pose(delta: float, A: Node) -> void:
	t += delta
	# Dance tempo: follows the estimated tempo when known, else the music's energy.
	var bpm: float = A.tempo_bpm if A.tempo_bpm > 60.0 else 90.0 + 50.0 * A.loudness
	var energy: float = 1.0 - A.silence_amount
	phase += delta * bpm / 60.0 * PI * (0.35 + 0.65 * energy)
	if A.beat > 0.9:
		step_side = -step_side
	hop = maxf(hop - delta * 4.0, A.beat * energy)
	sway = lerpf(sway, (0.35 + A.bass) * energy, 1.0 - exp(-4.0 * delta))
	lift = lerpf(lift, clampf(A.energy_slow * 1.4 + maxf(A.energy_delta, 0.0), 0.0, 1.0) * energy, 1.0 - exp(-1.5 * delta))
	arm = lerpf(arm, (0.3 + A.mid) * energy, 1.0 - exp(-5.0 * delta))
	spark = lerpf(spark, A.treble + A.snap * 0.5, 1.0 - exp(-8.0 * delta))
	queue_redraw()


func _draw() -> void:
	if character == "Pip":
		_draw_pip()
	else:
		_draw_lumen()


func _limb(a: Vector2, b: Vector2, c: Vector2, width: float, col: Color) -> void:
	draw_line(a, b, col, width, true)
	draw_line(b, c, col, width * 0.85, true)
	draw_circle(a, width * 0.5, col)
	draw_circle(b, width * 0.45, col)
	draw_circle(c, width * 0.42, col)


func _draw_lumen() -> void:
	var body := Color(0.16, 0.3, 0.36)
	var skin := Color(0.24, 0.4, 0.45)
	var scarf := Color(0.98, 0.78, 0.36)
	var s := sin(phase)
	var hip := Vector2(W * 0.5 + s * 16.0 * sway, 300.0 - hop * 16.0)
	var chest := hip + Vector2(s * 9.0 * sway, -112.0)
	var head := chest + Vector2(s * 5.0, -48.0)
	# Legs: alternate stepping, feet stay near the floor.
	for side in [-1.0, 1.0]:
		var up: float = maxf(sin(phase + (0.0 if side * step_side > 0.0 else PI)), 0.0) * 22.0 * sway
		var hip_j: Vector2 = hip + Vector2(side * 15.0, 4.0)
		var foot := Vector2(W * 0.5 + side * 34.0 + s * 6.0, 488.0 - up)
		var knee: Vector2 = (hip_j + foot) * 0.5 + Vector2(side * 10.0 + 6.0 * sway, -4.0)
		_limb(hip_j, knee, foot, 22.0, body)
	# A flowing skirt that swirls with the sway.
	var hem := PackedVector2Array([hip + Vector2(-20, -6), hip + Vector2(20, -6)])
	for i in 9:
		var f := 1.0 - i / 8.0
		var x := (f - 0.5) * 2.0
		hem.append(hip + Vector2(x * (58.0 + 14.0 * sway) + s * 18.0 * sway, 92.0 + sin(phase * 2.0 + x * 3.0) * 8.0 * sway))
	draw_colored_polygon(hem, body.lightened(0.08))
	# Torso.
	draw_colored_polygon(PackedVector2Array([hip + Vector2(-22, 6), hip + Vector2(22, 6), chest + Vector2(27, 0), chest + Vector2(-27, 0)]), body)
	draw_circle(chest, 27.0, body)
	# Arms: wave with the mids, rise as the music swells.
	for side in [-1.0, 1.0]:
		var sh: Vector2 = chest + Vector2(side * 27.0, 2.0)
		var wave: float = sin(phase * 2.0 + (0.0 if side > 0.0 else 1.6)) * arm
		var raise: float = lift * 1.4 + wave * 0.6
		var elbow: Vector2 = sh + Vector2(side * 34.0, 30.0 - raise * 60.0)
		var hand: Vector2 = elbow + Vector2(side * (24.0 + wave * 12.0), 30.0 - raise * 95.0)
		_limb(sh, elbow, hand, 17.0, skin)
	# Head and a flowing scarf.
	draw_circle(head, 26.0, skin)
	var scarf_pts := PackedVector2Array()
	for i in 12:
		var f := i / 11.0
		scarf_pts.append(chest + Vector2(-6.0 - f * 70.0 * (0.6 + sway * 0.5), -12.0 + f * 40.0 + sin(phase * 1.5 - f * 4.0) * 14.0 * f))
	draw_polyline(scarf_pts, scarf, 10.0, true)
	draw_line(chest + Vector2(-20, -14), chest + Vector2(20, -14), scarf, 12.0, true)


func _draw_pip() -> void:
	var body := Color(1.0, 0.56, 0.46)
	var belly := Color(1.0, 0.8, 0.68)
	var dark := Color(0.15, 0.1, 0.12)
	var squash := hop * 0.22
	var air := maxf(sin(phase), 0.0) * 30.0 * sway + hop * 40.0
	var center := Vector2(W * 0.5 + sin(phase * 0.5) * 12.0 * sway, 400.0 - air)
	var rx := 92.0 * (1.0 + squash)
	var ry := 82.0 * (1.0 - squash)
	# Feet.
	for side in [-1.0, 1.0]:
		var foot := Vector2(W * 0.5 + side * 46.0, 492.0 - maxf(air - 20.0, 0.0) * 0.5)
		draw_line(center + Vector2(side * 40.0, ry * 0.7), foot, body.darkened(0.25), 16.0, true)
		draw_circle(foot, 15.0, body.darkened(0.25))
	# Body (an ellipse from a polygon) and belly.
	var pts := PackedVector2Array()
	var belly_pts := PackedVector2Array()
	for i in 40:
		var a := i / 40.0 * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		belly_pts.append(center + Vector2(cos(a) * rx * 0.6, sin(a) * ry * 0.5 + ry * 0.3))
	draw_colored_polygon(pts, body)
	draw_colored_polygon(belly_pts, belly)
	# Antenna with a tip that glints with treble.
	var base := center + Vector2(0, -ry + 6.0)
	var tip := base + Vector2(sin(phase * 1.3) * 26.0 * (0.4 + arm), -70.0 + hop * 10.0)
	draw_line(base, tip, body.darkened(0.3), 6.0, true)
	draw_circle(tip, 11.0 + spark * 5.0, Color(1.0, 0.92, 0.6).lerp(Color.WHITE, spark))
	# Eyes (blink now and then).
	var blink := 1.0 if fmod(t, 4.3) > 0.12 else 0.15
	for side in [-1.0, 1.0]:
		var eye := center + Vector2(side * 30.0, -18.0)
		draw_set_transform(eye, 0.0, Vector2(1.0, blink))
		draw_circle(Vector2.ZERO, 15.0, Color.WHITE)
		draw_circle(Vector2(side * 2.0, 3.0), 7.5, dark)
		draw_set_transform(Vector2.ZERO)
	draw_arc(center + Vector2(0, 10.0), 14.0, 0.3, PI - 0.3, 12, dark, 4.0, true)
