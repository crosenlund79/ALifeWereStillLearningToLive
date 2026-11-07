extends ColorRect
## The living background. Shows the song's image (or the default / a procedural ambient
## scene) through one shader: crossfade between tracks, slow Ken Burns zoom and pan,
## gentle mouse parallax, bass breathing, treble shimmer, crescendo bloom, blur, dimming,
## colour wash and vignette. Images load on a worker thread, so decoding never blocks
## drawing; only the current and previous textures are kept alive.

const Common := preload("res://vis/common.gd")
const DEFAULT_IMAGE := "res://DeepForest.png"
const CROSSFADE := 2.2

var audio: Node
var shader_material := ShaderMaterial.new()
## Effect amounts (0..1), set from the active preset and per-song settings.
var fx := {
	"kenburns": 0.5, "parallax": 0.3, "breathing": 0.5, "vignette": 0.45, "dim": 0.2,
	"wash": 0.1, "blur": 0.0, "bloom": 0.25, "shimmer": 0.3,
}
var motion_scale := 1.0  # Per-song "background motion" multiplier.
var wash_color := Color(1.0, 0.8, 0.5)
var fallback_procedural := false
var tex_current: Texture2D
var tex_previous: Texture2D
var current_key := ""
var mix_ab := 1.0
var t := 0.0
var breath := 0.0
var bloom_boost := 0.0
var parallax := Vector2.ZERO
var _task := -1
var _pending_key := ""
var _loaded_image: Image
var _mutex := Mutex.new()
var _default_image: Image


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shader_material.shader = preload("res://vis/background.gdshader")
	material = shader_material
	color = Color.BLACK
	var img: Image = (load(DEFAULT_IMAGE) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	_default_image = img
	show_image("")


## Show an image file (absolute path), or "" for the fallback (default image or procedural).
func show_image(path: String) -> void:
	var key := path if path != "" else ("<procedural>" if fallback_procedural else "<default>")
	if key == current_key or key == _pending_key:
		return
	if key == "<default>":
		_set_texture(ImageTexture.create_from_image(_default_image), key)
	elif key == "<procedural>":
		_set_texture(null, key)
	else:
		_pending_key = key
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
		_task = WorkerThreadPool.add_task(_load_image.bind(path))


func _load_image(path: String) -> void:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img:
		if img.is_compressed():
			img.decompress()
		# Very large images are reduced so GPU memory stays modest.
		var longest := maxi(img.get_width(), img.get_height())
		if longest > 3840:
			var s := 3840.0 / longest
			img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
	_mutex.lock()
	_loaded_image = img
	_mutex.unlock()


func _set_texture(tex: Texture2D, key: String) -> void:
	tex_previous = tex_current if current_key != "" else tex
	var prev_proc := current_key == "<procedural>"
	tex_current = tex
	shader_material.set_shader_parameter("tex_b", tex_previous)
	shader_material.set_shader_parameter("tex_a", tex_current)
	shader_material.set_shader_parameter("size_b", tex_previous.get_size() if tex_previous else Vector2(16, 9))
	shader_material.set_shader_parameter("size_a", tex_current.get_size() if tex_current else Vector2(16, 9))
	shader_material.set_shader_parameter("proc_b", prev_proc if current_key != "" else tex == null)
	shader_material.set_shader_parameter("proc_a", tex == null)
	mix_ab = 0.0 if current_key != "" else 1.0
	current_key = key


func set_palette(primary: Color, secondary: Color) -> void:
	wash_color = primary
	shader_material.set_shader_parameter("proc_c1", secondary.darkened(0.6))
	shader_material.set_shader_parameter("proc_c2", primary)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	t += delta
	# Finish an image load started on a worker thread.
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		var img := _loaded_image
		_loaded_image = null
		_mutex.unlock()
		var key := _pending_key
		_pending_key = ""
		if img:
			_set_texture(ImageTexture.create_from_image(img), key)
		else:
			# Missing or unreadable image: quietly use the fallback.
			current_key = ""
			show_image("")
	mix_ab = minf(mix_ab + delta / CROSSFADE, 1.0)
	if mix_ab >= 1.0 and tex_previous != tex_current:
		tex_previous = tex_current  # Release the old texture once the crossfade is done.
		shader_material.set_shader_parameter("tex_b", tex_previous)

	var bass: float = audio.bass if audio else 0.0
	var loud: float = audio.loudness if audio else 0.0
	var delta_e: float = audio.energy_delta if audio else 0.0
	var treble: float = audio.treble if audio else 0.0
	breath = Common.approach(breath, bass * 0.7 + (audio.kick * 0.3 if audio else 0.0), 6.0, delta)
	bloom_boost = Common.approach(bloom_boost, maxf(delta_e, 0.0) * 1.5 + loud * 0.3, 1.5, delta)

	var kb: float = fx.kenburns * motion_scale
	var zoom: float = 1.0 + 0.045 * kb * (0.5 + 0.5 * sin(t * 0.021)) + 0.018 * fx.breathing * breath + 0.012
	var margin: float = (1.0 - 1.0 / zoom) * 0.5
	var mouse := get_local_mouse_position() / size - Vector2(0.5, 0.5) if size.x > 0.0 else Vector2.ZERO
	parallax = parallax.lerp(mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * -0.4, 1.0 - exp(-2.0 * delta))
	var pan: Vector2 = Vector2(sin(t * 0.013), cos(t * 0.017)) * 0.7 * kb + parallax * fx.parallax * motion_scale
	pan = pan.clamp(Vector2(-1, -1), Vector2(1, 1)) * margin

	var m := shader_material
	m.set_shader_parameter("mix_ab", mix_ab)
	m.set_shader_parameter("screen", size)
	m.set_shader_parameter("zoom", zoom)
	m.set_shader_parameter("pan", pan)
	m.set_shader_parameter("t", t)
	m.set_shader_parameter("blur", fx.blur * 4.0 if Common.quality > Common.Quality.PERFORMANCE or fx.blur > 0.5 else 0.0)
	m.set_shader_parameter("bloom", (fx.bloom * (0.6 + bloom_boost)) if Common.quality != Common.Quality.PERFORMANCE else 0.0)
	m.set_shader_parameter("shimmer", fx.shimmer * treble)
	m.set_shader_parameter("dim", clampf(fx.dim * (1.0 - 0.25 * loud), 0.0, 0.9))
	m.set_shader_parameter("wash", fx.wash)
	m.set_shader_parameter("wash_color", wash_color)
	m.set_shader_parameter("vignette", fx.vignette)
