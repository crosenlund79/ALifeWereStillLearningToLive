extends Control
## Dancing companion overlay, drawn between the visualizers and the UI.
##
## Characters: the built-in procedural companions (see dancer_figure.gd), or sprite dancers
## from the external dancers/ folder: one subfolder per character holding transparent PNG
## frames (played in natural filename order) or a single PNG, with an optional dancer.cfg:
##   [dancer]
##   fps=12          ; frames per second at about 120 BPM
##   beat_sync=true  ; frame rate follows the music's estimated tempo
##   scale=1.0       ; size relative to the default
## The dancer is lit by the visualizer's own lights (see set_lights and
## dancer_light.gdshader). Motion reads the shared audio analysis; nothing is re-analysed.

const Figure := preload("res://vis/dancer_figure.gd")
const SHADER := preload("res://vis/dancer_light.gdshader")
const BUILTIN := ["Lumen", "Pip"]
const MAX_FRAMES := 240

var audio: Node
var dancers_dir := ""
var enabled := false
var character := ""
var light_strength := 0.6
var size_mul := 1.0
var rect := TextureRect.new()
var mat := ShaderMaterial.new()
var viewport := SubViewport.new()
var figure: Node2D = Figure.new()
var frames: Array[Texture2D] = []
var fps := 12.0
var beat_sync := true
var sprite_scale := 1.0
var frame_pos := 0.0
var bounce := 0.0
var sway := 0.0
var t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mat.shader = SHADER
	rect.material = mat
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(rect)
	viewport.size = Vector2i(int(Figure.W), int(Figure.H))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.add_child(figure)
	add_child(viewport)
	visible = false


## Built-ins first, then every subfolder of dancers/ that contains PNG images.
func list_characters() -> Array:
	var out: Array = BUILTIN.duplicate()
	if dancers_dir != "" and DirAccess.dir_exists_absolute(dancers_dir):
		var dirs := DirAccess.get_directories_at(dancers_dir)
		for d in dirs:
			for f in DirAccess.get_files_at(dancers_dir.path_join(d)):
				if f.get_extension().to_lower() == "png":
					out.append(d)
					break
	return out


func set_character(character_name: String) -> void:
	if character_name == character:
		return
	character = character_name
	frames.clear()
	frame_pos = 0.0
	if character in BUILTIN or not DirAccess.dir_exists_absolute(dancers_dir.path_join(character)):
		if not (character in BUILTIN):
			character = BUILTIN[0]
		figure.character = character
		rect.texture = viewport.get_texture()
		sprite_scale = 1.0
		return
	var dir := dancers_dir.path_join(character)
	var cfg := ConfigFile.new()
	cfg.load(dir.path_join("dancer.cfg"))
	fps = float(cfg.get_value("dancer", "fps", 12.0))
	beat_sync = bool(cfg.get_value("dancer", "beat_sync", true))
	sprite_scale = float(cfg.get_value("dancer", "scale", 1.0))
	var files: Array = Array(DirAccess.get_files_at(dir)).filter(func(f): return f.get_extension().to_lower() == "png")
	files.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for f in files.slice(0, MAX_FRAMES):
		var img := Image.load_from_file(dir.path_join(f))
		if img:
			var longest := maxi(img.get_width(), img.get_height())
			if longest > 1024:
				var k := 1024.0 / longest
				img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
			frames.append(ImageTexture.create_from_image(img))
	if frames.is_empty():
		set_character(BUILTIN[0])
	else:
		rect.texture = frames[0]


## Lights in this control's coordinates (= screen): positions, colours (alpha = intensity).
func set_lights(positions: PackedVector2Array, colors: PackedColorArray, count: int) -> void:
	mat.set_shader_parameter("light_pos", positions)
	mat.set_shader_parameter("light_col", colors)
	mat.set_shader_parameter("light_count", count)


func _process(delta: float) -> void:
	visible = enabled
	var procedural := frames.is_empty()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled and procedural else SubViewport.UPDATE_DISABLED
	if not enabled or audio == null or rect.texture == null:
		return
	delta = minf(delta, 0.1)
	t += delta
	var energy: float = 1.0 - audio.silence_amount
	bounce = maxf(bounce - delta * 4.0, audio.beat * energy)
	sway = lerpf(sway, audio.mid * energy, 1.0 - exp(-3.0 * delta))
	if procedural:
		figure.update_pose(delta, audio)
	else:
		var rate: float = (audio.tempo_bpm / 120.0 if beat_sync and audio.tempo_bpm > 60.0 else 0.6 + 0.6 * audio.loudness) * energy
		frame_pos += delta * fps * rate
		rect.texture = frames[int(frame_pos) % frames.size()]

	# Bottom-centre, scaled with the window (works at 800x600 and in the mini player).
	var tex_size := rect.texture.get_size()
	var h := size.y * 0.5 * size_mul * sprite_scale
	var w := h * tex_size.x / maxf(tex_size.y, 1.0)
	rect.size = Vector2(w, h)
	rect.pivot_offset = Vector2(w * 0.5, h)
	rect.position = Vector2(size.x * 0.5 - w * 0.5, size.y - h - size.y * 0.02)
	if procedural:
		rect.rotation = 0.0
		rect.scale = Vector2.ONE
	else:
		# Sprites get a gentle bounce and sway of their own.
		rect.rotation = sin(t * 1.7) * 0.04 * sway
		rect.scale = Vector2(1.0 + bounce * 0.03, 1.0 - bounce * 0.05)
	mat.set_shader_parameter("strength", light_strength)
	mat.set_shader_parameter("tex_px", Vector2.ONE / tex_size)
	mat.set_shader_parameter("screen_h", maxf(size.y, 1.0))
