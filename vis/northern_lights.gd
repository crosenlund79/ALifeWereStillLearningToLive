extends RefCounted
## NORTHERN LIGHTS — curtains of rays hanging in a starlit sky (shader-based).
##
## Unlike The Aurora (horizontal flowing ribbons), these are vertical-ray curtains at
## different heights, folding sideways, with sharp lower edges fading upward into a second
## colour, over a twinkling star field. Each curtain follows its own frequency range (top =
## treble, bottom = bass); treble speeds up the ray shimmer; loudness and beats raise the
## light. Drawn by one full-screen shader (additive), so it is cheap.
## Settings: Curtains, Movement, Glow, Speed, colours (curtains from the element palette,
## upper colour = second colour).

const SHADER := preload("res://vis/northern_lights.gdshader")

var L: Control
var A: Node
var rect := ColorRect.new()
var mat := ShaderMaterial.new()
var t := 0.0
var energy := Vector4.ZERO


func _init(layer: Control, _mode: String) -> void:
	L = layer
	A = layer.audio
	mat.shader = SHADER
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	L.add_child(rect)


func dispose() -> void:
	rect.queue_free()


func element_count() -> int:
	return clampi(int(L.p("count", 3)), 1, 4)


func update(delta: float) -> void:
	t += delta * (0.6 + 0.6 * A.mid)
	var n := element_count()
	var target := Vector4.ZERO
	for k in n:
		# Top curtain = treble ... bottom curtain = bass.
		var b0 := int(floor((n - 1 - k) * 7.0 / n))
		var b1 := maxi(int(floor((n - k) * 7.0 / n)), b0 + 1)
		var e: float = 0.0
		for b in range(b0, b1):
			e += float(A.bands7[b])
		target[k] = e / (b1 - b0) * L.intensity
	for k in 4:
		energy[k] = lerpf(energy[k], target[k], 1.0 - exp(-(10.0 if target[k] > energy[k] else 3.0) * delta))
	mat.set_shader_parameter("t", t)
	mat.set_shader_parameter("count", n)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("treble", A.treble)
	mat.set_shader_parameter("loud", A.loudness * (1.0 - A.silence_amount * 0.5))
	mat.set_shader_parameter("flash", A.beat_light)
	mat.set_shader_parameter("glow", L.glow)
	mat.set_shader_parameter("move", L.p("range", 1.0))
	mat.set_shader_parameter("aspect", L.size.x / maxf(L.size.y, 1.0))
	for k in 4:
		mat.set_shader_parameter("col%d" % k, L.color(k))
	mat.set_shader_parameter("top_col", L.secondary)


func draw() -> void:
	pass  # The shader rect draws itself.
