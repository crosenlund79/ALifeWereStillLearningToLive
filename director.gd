extends Node
## Visual director: builds the visual layer stack and shows ONE global look.
##
## The look (visualizers, colours, effects, background) is global: changing songs or moods
## never changes it. It is saved in visualizer.json and restored at launch. Presets are
## optional starting points chosen by hand (Visualizers tab, keys 1-9, [ and ]).
## Also handles track notifications, toasts, screenshots, the diagnostics overlay (F3)
## and cursor hiding.

signal preset_changed(preset_name: String)
signal working_changed

const Common := preload("res://vis/common.gd")
const Layer := preload("res://vis/visual_layer.gd")
const Presets := preload("res://presets.gd")
const LIGHT_FONT := preload("res://Font/LEMONMILK-Light.otf")
const BOLD_FONT := preload("res://Font/LEMONMILK-Bold.otf")
const GOLD := Color(0.96, 0.82, 0.52)

@onready var audio: Node = $"../Audio"
@onready var background: ColorRect = $"../Background"
@onready var visuals: Control = $"../Visuals"
@onready var music: AudioStreamPlayer = $"../Music"
@onready var ui: Control = $"../UI"

var presets := Presets.new()
var layers := {}  # role -> layer node
var working := {}  # The global look on screen (edits change it live and are saved).
var working_name := ""
var look_path := ""
var color_a := Color(1.0, 0.82, 0.45)
var color_b := Color(0.8, 0.5, 0.32)
var palette: Array = []  # 7 element colours on screen (blending toward the target)
var _tween: Tween
var _save_timer := -1.0
var _cursor_idle := 0.0
var _diag_timer := 0.0

var hud := Control.new()
var notify_box := VBoxContainer.new()
var notify_title := Label.new()
var notify_artist := Label.new()
var toast := Label.new()
var diag := Label.new()
var rec_label := Label.new()
var _notify_tween: Tween
var _toast_tween: Tween


func _ready() -> void:
	Common.quality = int(music.app_setting("quality", Common.Quality.BALANCED)) as Common.Quality
	audio.sensitivity = float(music.app_setting("sensitivity", 100.0)) / 100.0
	audio.adaptive = music.app_setting("adaptive", true)
	background.audio = audio
	background.fallback_procedural = music.app_setting("fallback_procedural", false)
	presets.load_file(music.base_dir.path_join("presets.json"))
	look_path = music.base_dir.path_join("visualizer.json")

	for role in ["atmosphere", "secondary", "main", "beatlight"]:
		var layer: Control = Layer.new()
		layer.name = role.capitalize()
		layer.audio = audio
		visuals.add_child(layer)
		layers[role] = layer

	_build_hud()
	music.track_changed.connect(_on_track_changed)
	music.notice.connect(show_toast)
	get_viewport().size_changed.connect(func(): working_changed.emit())
	apply_preset(_load_look(), false)
	apply_background()
	_on_track_changed(music.current)


# --- The global look ------------------------------------------------------------------

## The saved look; on first run after an update, the preset that used to be global.
func _load_look() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(look_path)) if FileAccess.file_exists(look_path) else null
	if data is Dictionary and data.get("look") is Dictionary:
		return data.look
	var old := str(music.app_setting("preset", "Seven Souls"))
	if music.settings.has_section_key(music.APP, "preset"):
		music.settings.erase_section_key(music.APP, "preset")
		music.settings.save(music.config_path)
	return presets.get_preset(old if old in presets.names() else presets.names()[0])


func _save_look() -> void:
	var f := FileAccess.open(look_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"schema": 1, "look": working}, "\t"))


func _exit_tree() -> void:
	if _save_timer >= 0.0:
		_save_look()


## Applies a look (a preset chosen by hand, or the saved look) as the global look.
func apply_preset(p: Dictionary, animate := true) -> void:
	if p.is_empty():
		return
	working = Presets.complete(p)
	working_name = working.name
	if animate and visuals.modulate.a > 0.01:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(visuals, "modulate:a", 0.0, 0.45)
		_tween.tween_callback(_apply_modes)
		_tween.tween_property(visuals, "modulate:a", 1.0, 0.9)
	else:
		_apply_modes()
	_save_timer = 1.0
	preset_changed.emit(working_name)
	working_changed.emit()


func _apply_modes() -> void:
	var main_cfg: Dictionary = working.main
	var sec_cfg: Dictionary = working.secondary
	# Avoid clutter: never the same visualizer twice.
	if sec_cfg.mode == main_cfg.mode:
		sec_cfg.mode = "none"
	layers.main.set_mode(main_cfg.mode)
	layers.main.set_blend(main_cfg.additive)
	layers.secondary.set_mode(sec_cfg.mode)
	layers.secondary.set_blend(sec_cfg.additive)
	layers.atmosphere.set_mode(working.atmosphere.mode)
	layers.atmosphere.set_blend(true)
	layers.beatlight.set_mode("beatlight" if float(working.beat_light) > 0.0 else "none")
	layers.beatlight.set_blend(true)
	background.fx = working.background.duplicate()


## Live edit: section ("main", "secondary", "atmosphere", "background" or "" for top-level
## keys), key and value. Changes show immediately and are saved as the global look.
func edit(section: String, key: String, value: Variant) -> void:
	if section == "":
		working[key] = value
	else:
		working[section][key] = value
	if key in ["mode", "additive", "beat_light"] or section == "background":
		_apply_modes()
	_save_timer = 1.0
	working_changed.emit()


## The global background image (a file in backgrounds/, or "" for the default).
func apply_background() -> void:
	var bg := str(music.app_setting("background", ""))
	var path: String = music.backgrounds_dir.path_join(bg)
	background.show_image(path if bg != "" and FileAccess.file_exists(path) else "")


func set_background(file: String) -> void:
	music.set_app_setting("background", file)
	apply_background()


func preview(preset_name: String) -> void:
	apply_preset(presets.get_preset(preset_name))


func restore_defaults() -> void:
	apply_preset(presets.get_preset(working_name), false)


func save_working(as_name := "") -> String:
	var p := working.duplicate(true)
	p.name = as_name if as_name != "" else working_name
	presets.save_preset(p)
	working_name = p.name
	working.name = p.name
	_save_timer = 1.0
	preset_changed.emit(working_name)
	show_toast("Saved preset " + working_name)
	return working_name


func duplicate_working() -> String:
	return save_working(presets.unique_name(working_name + " Copy"))


func rename_working(new_name: String) -> bool:
	if not presets.rename_preset(working_name, new_name):
		return false
	working_name = new_name
	working.name = new_name
	_save_timer = 1.0
	preset_changed.emit(working_name)
	return true


func delete_working() -> void:
	presets.delete_preset(working_name)
	apply_preset(presets.get_preset(presets.names()[0]))


func restore_builtins() -> void:
	presets.restore_builtins()
	preset_changed.emit(working_name)
	show_toast("Built-in presets restored")


func cycle_preset(step: int) -> void:
	var names := presets.names()
	var i := names.find(working_name)
	preview(names[wrapi(i + step, 0, names.size())])
	show_toast("Preset: " + working_name)


## Song changes only show the track pop-up: the look stays exactly as it is.
func _on_track_changed(_index: int) -> void:
	_show_notification()


# --- Per frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if working.is_empty():
		return
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			_save_look()

	# Colour changes blend over ~1.5 s.
	var rate := 1.0 - exp(-2.0 * delta)
	color_a = color_a.lerp(Color(working.colors[0]), rate)
	color_b = color_b.lerp(Color(working.colors[1]), rate)
	background.set_palette(color_a, color_b)
	var pal_src: Array = working.get("palette", Presets.PALETTE)
	if palette.size() != 7:
		palette = pal_src.map(func(c): return Color(c))
	for k in 7:
		palette[k] = (palette[k] as Color).lerp(Color(pal_src[k]), rate)

	for role in ["main", "secondary", "atmosphere"]:
		var cfg: Dictionary = working[role]
		var layer: Control = layers[role]
		layer.opacity = float(cfg.opacity) if role != "secondary" else minf(float(cfg.opacity), 0.8)
		layer.scale_factor = float(cfg.scale)
		layer.intensity = float(cfg.intensity)
		layer.speed = float(cfg.speed)
		layer.glow = float(cfg.glow)
		layer.trail = float(cfg.trail)
		layer.density = 0.6 if role == "secondary" else 1.0
		layer.primary = color_a
		layer.secondary = color_b
		layer.cfg = cfg
		layer.palette = palette
	var bl: Control = layers.beatlight
	bl.intensity = float(working.beat_light)
	bl.primary = color_a

	# The pop-up is for when the panel is hidden; the panel shows the title itself.
	notify_box.visible = not ui.overlay.visible and not ui.mini
	# Recording indicator: always visible while recording, even with the interface hidden.
	rec_label.visible = music.recording
	if music.recording:
		var secs := int(music.recording_seconds())
		var dot := "●" if int(Time.get_ticks_msec() / 600) % 2 == 0 else "○"
		rec_label.text = "%s REC %d:%02d%s" % [dot, secs / 60, secs % 60, "" if music.rec_format == "" else "  " + music.rec_format.to_upper()]
		rec_label.reset_size()
		rec_label.position.x = hud.size.x - rec_label.size.x - 24
	_update_cursor(delta)
	if diag.visible:
		_diag_timer += delta
		if _diag_timer > 0.25:
			_diag_timer = 0.0
			_update_diag()


func _update_cursor(delta: float) -> void:
	# Hide the pointer while the interface is hidden and the mouse is still.
	_cursor_idle += delta
	var should_hide: bool = not ui.overlay.visible and not ui.mini_panel.visible and _cursor_idle > 2.0
	var want := Input.MOUSE_MODE_HIDDEN if should_hide else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 0.5:
		_cursor_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var shot_key := OS.find_keycode_from_string(str(music.app_setting("screenshot_key", "F12")))
	if event.keycode == shot_key and shot_key != KEY_NONE:
		take_screenshot()
	elif event.keycode == KEY_F3:
		diag.visible = not diag.visible
		_update_diag()
	elif event.keycode == KEY_BRACKETLEFT:
		cycle_preset(-1)
	elif event.keycode == KEY_BRACKETRIGHT:
		cycle_preset(1)
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9 and not event.ctrl_pressed:
		var names := presets.names()
		var i: int = event.keycode - KEY_1
		if i < names.size():
			preview(names[i])
			show_toast("Preset: " + names[i])


# --- HUD: notifications, toasts, diagnostics ----------------------------------------

func _build_hud() -> void:
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	notify_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	notify_box.position = Vector2(36, 0)
	notify_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notify_box.offset_bottom = -40
	notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_box.modulate.a = 0.0
	hud.add_child(notify_box)
	for l in [notify_title, notify_artist]:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_y", 2)
		notify_box.add_child(l)
	notify_title.add_theme_font_override("font", BOLD_FONT)
	notify_title.add_theme_font_size_override("font_size", 24)
	notify_title.add_theme_color_override("font_color", Color(GOLD, 0.95))
	notify_artist.add_theme_font_override("font", LIGHT_FONT)
	notify_artist.add_theme_font_size_override("font_size", 15)
	notify_artist.add_theme_color_override("font_color", Color(GOLD, 0.75))

	toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.offset_right = -28
	toast.offset_bottom = -24
	toast.add_theme_font_override("font", LIGHT_FONT)
	toast.add_theme_font_size_override("font_size", 13)
	toast.add_theme_color_override("font_color", GOLD)
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	toast.add_theme_constant_override("shadow_offset_y", 1)
	toast.modulate.a = 0.0
	hud.add_child(toast)

	rec_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rec_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rec_label.offset_right = -24
	rec_label.offset_top = 14
	rec_label.add_theme_font_override("font", BOLD_FONT)
	rec_label.add_theme_font_size_override("font_size", 15)
	rec_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	rec_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	rec_label.add_theme_constant_override("shadow_offset_y", 1)
	rec_label.visible = false
	hud.add_child(rec_label)

	diag.position = Vector2(14, 12)
	diag.add_theme_font_size_override("font_size", 12)
	diag.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	diag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	diag.add_theme_constant_override("shadow_offset_y", 1)
	diag.visible = false
	hud.add_child(diag)


func _show_notification() -> void:
	if not music.app_setting("track_notification", true) or music.current_path == "":
		return
	if ui.hide_mode and not music.app_setting("notify_in_immersive", false):
		return
	var info: Dictionary = music.track_info(music.current_path)
	notify_title.text = str(info.title).to_upper()
	notify_artist.text = str(info.artist).to_upper()
	notify_artist.visible = info.artist != ""
	if _notify_tween:
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_property(notify_box, "modulate:a", 1.0, 0.8)
	_notify_tween.tween_interval(4.0)
	_notify_tween.tween_property(notify_box, "modulate:a", 0.0, 1.4)


func show_toast(text: String) -> void:
	toast.text = text
	toast.reset_size()
	# Above the transport bar while the panel is open.
	toast.position = hud.size - toast.size - Vector2(28, 84 if ui.overlay.visible or ui.mini else 24)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.8)


func _update_diag() -> void:
	var counts := 0
	var active := []
	for role in ["main", "secondary", "atmosphere", "beatlight"]:
		var l: Control = layers[role]
		if l.mode != "none":
			active.append("%s=%s(%.0f%%)" % [role, l.mode, l.opacity * 100.0])
			counts += l.element_count()
	diag.text = "\n".join([
		"TINSERBOX DIAGNOSTICS  (F3)",
		"FPS %d   quality %s   window %dx%d" % [Engine.get_frames_per_second(), ["performance", "balanced", "quality"][Common.quality], ui.size.x, ui.size.y],
		"layers: " + ", ".join(active),
		"elements: %d" % counts,
		"analyzer: %s   silence %s   adaptive %s" % ["ok" if audio.available else "MISSING", audio.silence, audio.adaptive],
		"bass %.2f  mid %.2f  treble %.2f  loud %.2f  delta %+.2f" % [audio.bass, audio.mid, audio.treble, audio.loudness, audio.energy_delta],
		"onset %.2f  kick %.2f  snap %.2f  beats %d  ~%d bpm (estimate)" % [audio.onset, audio.kick, audio.snap, audio.beat_count, audio.tempo_bpm],
		"look: %s   config: %s" % [working_name, look_path],
		"bus effects: %d" % AudioServer.get_bus_effect_count(0),
	])


# --- Screenshots --------------------------------------------------------------------

func screenshot_dir() -> String:
	var d := str(music.app_setting("screenshot_dir", ""))
	return d if d != "" else music.base_dir.path_join("screenshots")


func take_screenshot() -> void:
	var hide_ui: bool = music.app_setting("screenshot_hide_ui", true)
	var ui_was := ui.visible
	if hide_ui:
		ui.visible = false
		hud.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	ui.visible = ui_was
	hud.visible = true
	var dir := screenshot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var song: String = music.display_name(music.current_path) if music.current_path != "" else "TinserBox"
	for ch in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		song = song.replace(ch, "")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var base := "TinserBox_%s_%s" % [song.strip_edges(), stamp]
	var path := dir.path_join(base + ".png")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.png" % [base, n])
		n += 1
	if img and img.save_png(path) == OK:
		show_toast("Screenshot saved: " + path.get_file())
	else:
		show_toast("Screenshot could not be saved")
