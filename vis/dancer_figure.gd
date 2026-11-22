extends Node2D
## ARIA — the built-in dancing companion, drawn as an illustration in a 384x768 transparent
## SubViewport (so the visualizer-lighting shader works for her as for sprite dancers).
##
## Animation:
##  - A 2D skeleton: pelvis, spine, head, FK arms, IK legs (feet stay planted).
##  - Authored dance moves: key poses on beat positions within a 4-beat bar, interpolated
##    with "back" easing (anticipation before a move, overshoot after) and smoothed by springs
##    (follow-through and recovery). Hair and skirt are spring chains that trail the body.
##  - A beat clock follows the estimated tempo and is nudged toward detected beats.
##  - Every bar a move is chosen for the music's energy (quiet: swaying; medium: steps,
##    waves, grooves; strong: bounces, claps, reaching up; crescendos call for reach-up).
##    Moves cross-fade at the bar line. Movement size follows the energy.
##  - Personalities (shy, playful, energetic, elegant, clumsy) change amplitude, easing,
##    timing feel and which moves are preferred.

const W := 384.0
const H := 768.0
const FLOOR := 742.0
const HIP_Y := 468.0  # legs slightly bent at rest so dips bend the knees
const THIGH := 150.0
const SHIN := 146.0
const TORSO := 168.0
const UPPER_ARM := 92.0
const FOREARM := 84.0

const SKIN := Color(0.93, 0.76, 0.63)
const SKIN_SHADE := Color(0.80, 0.60, 0.50)
const HAIR := Color(0.42, 0.17, 0.12)
const DRESS := Color(0.17, 0.21, 0.45)
const TRIM := Color(0.96, 0.78, 0.40)
const SHOE := Color(0.18, 0.12, 0.14)

const NEUTRAL := {
	"hx": 0.0, "hy": 0.0, "tilt": 0.0, "lean": 0.0, "head": 0.0,
	"las": 0.28, "lae": 0.35, "ras": 0.28, "rae": 0.35,
	"lfx": -36.0, "lfy": 0.0, "rfx": 36.0, "rfy": 0.0,
}

## Moves: [beat position (0..4), pose changes from NEUTRAL]. Beat 4 loops to beat 0.
const MOVES := {
	"idle": [
		[0.0, {"hy": 0.0}], [2.0, {"hy": 3.0, "head": 0.03}],
	],
	"sway": [
		[0.0, {"hx": -20.0, "tilt": -0.08, "lean": 0.05, "head": 0.10, "las": 0.40, "ras": 0.18}],
		[1.0, {"hy": 5.0}],
		[2.0, {"hx": 20.0, "tilt": 0.08, "lean": -0.05, "head": -0.10, "las": 0.18, "ras": 0.40}],
		[3.0, {"hy": 5.0}],
	],
	"step_touch": [
		[0.0, {"hx": -24.0, "lfx": -64.0, "rfx": -10.0, "rfy": 14.0, "las": 0.55, "lae": 1.5, "ras": 0.20, "tilt": -0.10, "head": 0.12}],
		[1.0, {"hy": 12.0}],
		[2.0, {"hx": 24.0, "rfx": 64.0, "lfx": 10.0, "lfy": 14.0, "ras": 0.55, "rae": 1.5, "las": 0.20, "tilt": 0.10, "head": -0.12}],
		[3.0, {"hy": 12.0}],
	],
	"arm_wave": [
		[0.0, {"las": 2.45, "lae": 0.45, "ras": 0.5, "rae": 0.6, "hx": -12.0, "head": 0.12, "hy": 4.0}],
		[1.0, {"las": 1.2, "lae": 1.1, "ras": 1.2, "rae": 1.1, "hy": 10.0}],
		[2.0, {"las": 0.5, "lae": 0.6, "ras": 2.45, "rae": 0.45, "hx": 12.0, "head": -0.12, "hy": 4.0}],
		[3.0, {"las": 1.2, "lae": 1.1, "ras": 1.2, "rae": 1.1, "hy": 10.0}],
	],
	"bounce_clap": [
		[0.0, {"hy": 18.0, "las": 0.9, "lae": 2.3, "ras": 0.9, "rae": 2.3, "head": 0.06}],
		[0.5, {"hy": -6.0, "las": 1.3, "lae": 0.7, "ras": 1.3, "rae": 0.7}],
		[1.0, {"hy": 18.0, "las": 2.0, "lae": 2.0, "ras": 2.0, "rae": 2.0, "head": -0.06}],
		[1.5, {"hy": -6.0, "las": 1.3, "lae": 0.7, "ras": 1.3, "rae": 0.7}],
		[2.0, {"hy": 18.0, "las": 0.9, "lae": 2.3, "ras": 0.9, "rae": 2.3, "head": 0.06}],
		[2.5, {"hy": -6.0, "las": 1.3, "lae": 0.7, "ras": 1.3, "rae": 0.7, "lfy": 10.0}],
		[3.0, {"hy": 18.0, "las": 2.0, "lae": 2.0, "ras": 2.0, "rae": 2.0, "head": -0.06}],
		[3.5, {"hy": -6.0, "las": 1.3, "lae": 0.7, "ras": 1.3, "rae": 0.7, "rfy": 10.0}],
	],
	"reach_up": [
		[0.0, {"las": 2.55, "lae": -0.25, "ras": 2.55, "rae": -0.25, "head": -0.16, "hy": -4.0}],
		[1.0, {"hx": -18.0, "tilt": -0.1, "las": 2.35, "lae": -0.1, "ras": 2.65, "rae": -0.3, "lean": 0.06, "hy": 6.0}],
		[2.0, {"hy": 14.0, "las": 2.5, "lae": -0.2, "ras": 2.5, "rae": -0.2}],
		[3.0, {"hx": 18.0, "tilt": 0.1, "las": 2.65, "lae": -0.3, "ras": 2.35, "rae": -0.1, "lean": -0.06, "hy": 6.0}],
	],
	"groove": [
		[0.0, {"hy": 14.0, "tilt": -0.13, "las": 1.0, "lae": 2.0, "ras": 0.5, "rae": 1.2, "lfy": 9.0, "head": 0.14}],
		[1.0, {"hy": 0.0, "tilt": 0.0, "las": 0.8, "lae": 1.6, "ras": 0.8, "rae": 1.6}],
		[2.0, {"hy": 14.0, "tilt": 0.13, "ras": 1.0, "rae": 2.0, "las": 0.5, "lae": 1.2, "rfy": 9.0, "head": -0.14}],
		[3.0, {"hy": 0.0, "tilt": 0.0, "las": 0.8, "lae": 1.6, "ras": 0.8, "rae": 1.6}],
	],
}
const TIERS := {
	"calm": ["sway", "sway", "arm_wave"],
	"medium": ["step_touch", "arm_wave", "groove", "sway"],
	"high": ["bounce_clap", "reach_up", "groove", "step_touch"],
}
## amp: movement size; snap: easing overshoot (0 = smooth); stiff: spring stiffness;
## lag: timing behind the beat (in beats); prefer: favourite moves.
const PERSONALITIES := {
	"shy": {"amp": 0.55, "snap": 0.0, "stiff": 9.0, "lag": 0.10, "head": 0.18, "prefer": ["sway", "step_touch"]},
	"playful": {"amp": 1.0, "snap": 1.3, "stiff": 16.0, "lag": 0.0, "head": 0.0, "prefer": ["bounce_clap", "step_touch", "groove"]},
	"energetic": {"amp": 1.3, "snap": 1.0, "stiff": 22.0, "lag": -0.03, "head": 0.0, "prefer": ["bounce_clap", "reach_up", "groove"]},
	"elegant": {"amp": 0.9, "snap": 0.0, "stiff": 8.0, "lag": 0.05, "head": -0.05, "prefer": ["arm_wave", "sway", "reach_up"]},
	"clumsy": {"amp": 1.05, "snap": 1.6, "stiff": 11.0, "lag": 0.0, "head": 0.0, "prefer": ["step_touch", "bounce_clap"]},
}

var character := "Aria"
var personality := "playful"
var t := 0.0
var beat := 0.0  # beat clock (bars of 4)
var energy := 0.0
var move := "idle"
var prev_move := "idle"
var blend := 1.0  # 0 -> previous move, 1 -> current move
var bar := -1
var pose := NEUTRAL.duplicate()
var vel := {}
var hair: Array[Vector2] = []
var hair_prev: Array[Vector2] = []
var hem := PackedFloat32Array()  # skirt hem horizontal offsets (springs)
var hem_vel := PackedFloat32Array()
var last_hip := Vector2.ZERO
var wobble := 0.0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	for k in NEUTRAL:
		vel[k] = 0.0
	for i in 7:
		hair.append(Vector2(W * 0.5 + 30.0, 210.0 + i * 16.0))
		hair_prev.append(hair[i])
	hem.resize(9)
	hem_vel.resize(9)
	rng.randomize()


func _p() -> Dictionary:
	return PERSONALITIES.get(personality, PERSONALITIES.playful)


func update_pose(delta: float, A: Node) -> void:
	t += delta
	var per := _p()
	# Energy: how strongly to dance (quiet passages stay gentle).
	var target_e: float = clampf(A.loudness * 0.55 + A.energy_slow * 0.6, 0.0, 1.0) * (1.0 - A.silence_amount)
	energy = lerpf(energy, target_e, 1.0 - exp(-1.5 * delta))
	# Beat clock: tempo estimate folded into a comfortable dance range, nudged toward beats.
	var bpm: float = A.tempo_bpm
	if bpm < 60.0:
		bpm = 88.0 + 30.0 * energy
	while bpm > 140.0:
		bpm *= 0.5
	while bpm < 75.0:
		bpm *= 2.0
	beat += delta * bpm / 60.0 * (0.25 if A.silence_amount > 0.8 else 1.0)
	if A.beat > 0.95:
		beat += (round(beat) - beat) * 0.35
	# A new bar: choose the next move for the current energy and personality.
	var this_bar := int(floor(beat / 4.0))
	if this_bar != bar:
		bar = this_bar
		_choose_move(A, per)
	blend = minf(blend + delta * bpm / 60.0 / 0.6, 1.0)  # cross-fade over ~0.6 beat

	var b := fposmod(beat - per.lag + (rng.randf_range(-0.05, 0.05) if personality == "clumsy" else 0.0), 4.0)
	var amp: float = per.amp * (0.22 + 0.85 * energy)
	var a_pose := _sample(move, b, per.snap)
	var b_pose := _sample(prev_move, b, per.snap)
	# Springs toward the target pose give follow-through and recovery.
	var stiff: float = per.stiff
	for k in NEUTRAL:
		var target: float = NEUTRAL[k] + lerpf(b_pose.get(k, 0.0), a_pose.get(k, 0.0), blend) * amp
		if k == "head":
			target += per.head
		var acc: float = (target - pose[k]) * stiff * stiff - vel[k] * 2.0 * stiff * 0.7
		vel[k] += acc * delta
		pose[k] += vel[k] * delta
	if personality == "clumsy":
		wobble = lerpf(wobble, sin(t * 3.1) * 0.05 * energy, 1.0 - exp(-2.0 * delta))
		pose.lean += wobble
	_secondary(delta)
	queue_redraw()


func _choose_move(A: Node, per: Dictionary) -> void:
	var tier := "calm" if energy < 0.33 else ("medium" if energy < 0.62 else "high")
	if A.silence_amount > 0.8:
		tier = ""
	var options: Array = TIERS.get(tier, ["idle"])
	var next := "idle"
	if A.energy_delta > 0.15 and tier == "high":
		next = "reach_up"  # a crescendo lifts the arms
	elif not options.is_empty():
		# Favourite moves are twice as likely; avoid the same move three bars running.
		var bag: Array = []
		for m in options:
			bag.append(m)
			if m in per.prefer:
				bag.append(m)
		next = bag[rng.randi() % bag.size()]
		if next == move and next == prev_move and options.size() > 1:
			next = options[(options.find(next) + 1) % options.size()]
	if next != move:
		prev_move = move
		move = next
		blend = 0.0


## Pose (changes from neutral) of `move_name` at beat position b (0..4).
func _sample(move_name: String, b: float, snap: float) -> Dictionary:
	var keys: Array = MOVES[move_name]
	var n := keys.size()
	var i := n - 1
	for k in n:
		if keys[k][0] <= b:
			i = k
	var j := (i + 1) % n
	var t0: float = keys[i][0]
	var t1: float = keys[j][0] if j > i else 4.0 + float(keys[j][0])
	var u := clampf((b - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	var e := _ease(u, snap)
	var out := {}
	var pa: Dictionary = keys[i][1]
	var pb: Dictionary = keys[j][1]
	for k in NEUTRAL:
		out[k] = lerpf(float(pa.get(k, 0.0)), float(pb.get(k, 0.0)), e)
	return out


## Back easing: a small wind-up before the motion and an overshoot after (snap = 0 is smooth).
func _ease(x: float, snap: float) -> float:
	if snap <= 0.01:
		return x * x * (3.0 - 2.0 * x)
	var c := snap * 1.525
	if x < 0.5:
		return (pow(2.0 * x, 2.0) * ((c + 1.0) * 2.0 * x - c)) / 2.0
	return (pow(2.0 * x - 2.0, 2.0) * ((c + 1.0) * (x * 2.0 - 2.0) + c) + 2.0) / 2.0


## Hair and skirt trail the body (verlet chain and springs).
func _secondary(delta: float) -> void:
	var hip := Vector2(W * 0.5 + pose.hx, HIP_Y + pose.hy)
	var hip_vel := (hip - last_hip) / maxf(delta, 0.001)
	last_hip = hip
	var head := _head_pos()
	hair[0] = head + Vector2(26.0, -22.0).rotated(pose.head)
	for i in range(1, hair.size()):
		var p := hair[i]
		var v := (p - hair_prev[i]) * 0.9
		hair_prev[i] = p
		hair[i] = p + v + Vector2(0, 900.0) * delta * delta
		var d := hair[i] - hair[i - 1]
		hair[i] = hair[i - 1] + d.normalized() * 15.0 if d.length() > 0.01 else hair[i - 1] + Vector2(0, 15)
	for i in hem.size():
		var target := -hip_vel.x * 0.06 * (0.5 + float(i % 3) * 0.25)
		hem_vel[i] += ((target - hem[i]) * 40.0 - hem_vel[i] * 6.0) * delta
		hem[i] += hem_vel[i] * delta


func _head_pos() -> Vector2:
	var hip := Vector2(W * 0.5 + pose.hx, HIP_Y + pose.hy)
	var chest := hip + Vector2(0, -TORSO).rotated(pose.tilt * 0.5 + pose.lean)
	return chest + Vector2(0, -62.0).rotated(pose.lean + pose.head * 0.5)


func _draw() -> void:
	var hip := Vector2(W * 0.5 + pose.hx, HIP_Y + pose.hy)
	var spine: float = pose.tilt * 0.5 + pose.lean
	var chest := hip + Vector2(0, -TORSO).rotated(spine)
	var head := _head_pos()
	var across := Vector2(1, 0).rotated(spine)
	var pel := Vector2(1, 0).rotated(pose.tilt)

	# Hair behind the head (ponytail chain).
	var hair_line := PackedVector2Array(hair)
	draw_polyline(hair_line, HAIR.darkened(0.15), 22.0, true)
	draw_polyline(hair_line, HAIR.lightened(0.12), 8.0, true)

	# Legs (IK so the feet stay planted).
	for side in [-1.0, 1.0]:
		var hip_j: Vector2 = hip + pel * side * 18.0
		var fx: float = pose.lfx if side < 0.0 else pose.rfx
		var fy: float = pose.lfy if side < 0.0 else pose.rfy
		var foot := Vector2(W * 0.5 + fx + pose.hx * 0.25, FLOOR - fy)
		var knee := _ik(hip_j, foot, THIGH, SHIN, side)
		_limb(hip_j, knee, 17.0, 13.0, SKIN)
		_limb(knee, foot, 13.0, 9.0, SKIN)
		draw_colored_polygon(PackedVector2Array([foot + Vector2(-10 + side * 4, -6), foot + Vector2(16 * side + 4, -4), foot + Vector2(18 * side + 4, 6), foot + Vector2(-12 + side * 4, 6)]), SHOE)

	# Skirt: flares from the waist, the hem trails the movement.
	var waist_l := hip + pel * -30.0 + Vector2(0, -26)
	var waist_r := hip + pel * 30.0 + Vector2(0, -26)
	var skirt := PackedVector2Array([waist_l, waist_r])
	var skirt_cols := PackedColorArray([DRESS.lightened(0.1), DRESS.lightened(0.1)])
	var trim := PackedVector2Array()
	for i in hem.size():
		var f := 1.0 - float(i) / (hem.size() - 1)
		var x := (f - 0.5) * 2.0
		var wave := sin(t * 4.0 + x * 3.0) * 4.0 * energy
		var p := hip + (Vector2(x * (84.0 + 10.0 * energy) + hem[i], 128.0 + wave + absf(x) * -6.0)).rotated(pose.tilt * 0.6)
		skirt.append(p)
		skirt_cols.append(DRESS.darkened(0.25))
		trim.append(p)
	draw_polygon(skirt, skirt_cols)
	trim.reverse()
	draw_polyline(trim, TRIM, 5.0, true)

	# Torso (bodice) with shading and a gold neckline.
	var sh_l := chest - across * 36.0
	var sh_r := chest + across * 36.0
	var mid := hip.lerp(chest, 0.45)
	var waist_in := Vector2(1, 0).rotated(spine) * 22.0
	draw_polygon(PackedVector2Array([waist_l, mid - waist_in, sh_l + Vector2(0, 10), chest + Vector2(0, -4), sh_r + Vector2(0, 10), mid + waist_in, waist_r]),
		PackedColorArray([DRESS.lightened(0.04), DRESS.lightened(0.1), DRESS.lightened(0.16), DRESS.lightened(0.08), DRESS.darkened(0.06), DRESS.darkened(0.14), DRESS.darkened(0.1)]))
	draw_circle(chest + Vector2(0, 10), 30.0, DRESS.lightened(0.06))
	draw_line(mid - waist_in, mid + waist_in, TRIM.darkened(0.15), 4.0, true)  # sash
	draw_arc(chest + Vector2(0, -6), 18.0, 0.2, PI - 0.2, 12, TRIM, 4.0, true)

	# Arms (forward kinematics; elbows fold toward the body).
	for side in [-1.0, 1.0]:
		var sh: Vector2 = sh_l if side < 0.0 else sh_r
		var a_sh: float = pose.las if side < 0.0 else pose.ras
		var a_el: float = pose.lae if side < 0.0 else pose.rae
		var up_ang: float = PI * 0.5 + spine + (a_sh if side < 0.0 else -a_sh)
		var elbow: Vector2 = sh + Vector2.from_angle(up_ang) * UPPER_ARM
		var fo_ang: float = up_ang + (a_el if side < 0.0 else -a_el)
		var hand: Vector2 = elbow + Vector2.from_angle(fo_ang) * FOREARM
		_limb(sh, elbow, 12.0, 10.0, SKIN)
		_limb(elbow, hand, 10.0, 7.5, SKIN)
		var palm := hand + Vector2.from_angle(fo_ang) * 8.0
		draw_set_transform(palm, fo_ang, Vector2(1.3, 0.8))
		draw_circle(Vector2.ZERO, 9.0, SKIN.lightened(0.05))
		draw_set_transform(Vector2.ZERO)
		draw_circle(sh, 13.0, DRESS.lightened(0.12))  # puff sleeve

	# Neck and head.
	_limb(chest + Vector2(0, -12), head + Vector2(0, 24), 11.0, 10.0, SKIN_SHADE)
	draw_set_transform(head, pose.head * 0.6 + spine, Vector2.ONE)
	draw_circle(Vector2(18, -10), 30.0, HAIR.darkened(0.1))  # hair volume behind
	draw_circle(Vector2.ZERO, 36.0, SKIN)
	# Hair cap and fringe.
	var cap := PackedVector2Array()
	for i in 17:
		var a := PI + i / 16.0 * PI
		cap.append(Vector2(cos(a) * 40.0, sin(a) * 42.0 - 4.0))
	cap.append(Vector2(30, -6))
	cap.append(Vector2(6, -18))
	cap.append(Vector2(-14, -10))
	cap.append(Vector2(-36, -2))
	draw_colored_polygon(cap, HAIR)
	draw_arc(Vector2(-6, -12), 26.0, PI * 1.15, PI * 1.55, 8, HAIR.lightened(0.22), 4.0, true)
	# Face: closed, happy eyes when dancing strongly; open eyes otherwise.
	var happy := energy > 0.55 or personality == "elegant"
	for side in [-1.0, 1.0]:
		var e := Vector2(side * 14.0, 4.0)
		if happy:
			draw_arc(e + Vector2(0, 3), 6.0, PI * 1.1, PI * 1.9, 8, HAIR.darkened(0.5), 2.5, true)
		else:
			draw_circle(e, 4.2, HAIR.darkened(0.6))
			draw_circle(e + Vector2(-1.2, -1.4), 1.3, Color(1, 1, 1, 0.9))
		draw_circle(Vector2(side * 22.0, 16.0), 6.0, Color(0.95, 0.5, 0.5, 0.35))
	draw_arc(Vector2(0, 14), 8.0, 0.35, PI - 0.35, 10, Color(0.6, 0.25, 0.25), 2.5, true)
	draw_set_transform(Vector2.ZERO)


## Two-bone IK: the knee position for a leg from hip to foot (knees bend outward).
func _ik(root: Vector2, target: Vector2, l1: float, l2: float, side: float) -> Vector2:
	var to := target - root
	var d := clampf(to.length(), 1.0, l1 + l2 - 0.5)
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	return root + Vector2.from_angle(to.angle() - a * side * 0.55) * l1


## A tapered, softly shaded limb segment (lit from the upper left).
func _limb(a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var n := dir.orthogonal()
	draw_polygon(PackedVector2Array([a + n * wa, b + n * wb, b - n * wb, a - n * wa]),
		PackedColorArray([col.darkened(0.12), col.darkened(0.12), col.lightened(0.1), col.lightened(0.1)]))
	draw_circle(a, wa, col)
	draw_circle(b, wb, col)
