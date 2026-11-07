extends Node
## Scene director: builds the visual layer stack and decides what it shows.
##
## Effective look = preset (global, the song's own, or chosen automatically)
##                  x per-song adjustments (colours, intensity, glow, motion, density, sensitivity)
##                  x automatic personality modifiers (auto mode only, changing slowly).
## Also handles preset transitions, track notifications, toasts, screenshots, the
## diagnostics overlay (F3), cursor hiding and preset hotkeys (1-9, [ and ]).

signal preset_changed(preset_name: String)
signal working_changed

const Common := preload("res://vis/common.gd")
const Layer := preload("res://vis/visual_layer.gd")
const Presets := preload("res://presets.gd")
const LIGHT_FONT := preload("res://Font/LEMONMILK-Light.otf")
const BOLD_FONT := preload("res://Font/LEMONMILK-Bold.otf")
const GOLD := Color(0.96, 0.82, 0.52)
const SONG_KEYS := ["preset_mode", "preset", "color", "color2", "sensitivity", "glow", "bg_motion", "particle_density", "intensity", "background"]

@onready var audio: Node = $"../Audio"
@onready var background: ColorRect = $"../Background"
@onready var visuals: Control = $"../Visuals"
@onready var music: AudioStreamPlayer = $"../Music"
@onready var ui: Control = $"../UI"

var presets := Presets.new()
var layers := {}  # role -> layer node
var working := {}  # The preset currently on screen (Studio edits change this live).
var working_name := ""
var source := "global"  # global | song | auto
var auto_choice := ""
var auto_reason := ""
var mods := {"speed": 1.0, "glow": 1.0, "density": 1.0, "intensity": 1.0, "motion": 1.0}
var mods_target := mods.duplicate()
var color_a := Color(1.0, 0.82, 0.45)
var color_b := Color(0.8, 0.5, 0.32)
var _tween: Tween
var _auto_timer := 0.0
var _cursor_idle := 0.0
var _diag_timer := 0.0

var hud := Control.new()
var notify_box := VBoxContainer.new()
var notify_title := Label.new()
var notify_artist := Label.new()
var toast := Label.new()
var diag := Label.new()
var _notify_tween: Tween
var _toast_tween: Tween


func _ready() -> void:
	Common.quality = int(music.app_setting("quality", Common.Quality.BALANCED)) as Common.Quality
	audio.sensitivity = float(music.app_setting("sensitivity", 100.0)) / 100.0
	audio.adaptive = music.app_setting("adaptive", true)
	background.audio = audio
	background.fallback_procedural = music.app_setting("fallback_procedural", false)
	presets.load_file(music.base_dir.path_join("presets.json"))

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
	_on_track_changed(music.current)


# --- Presets ------------------------------------------------------------------------

func global_preset_name() -> String:
	var n: String = music.app_setting("preset", "Seven Souls")
	return n if n in presets.names() else presets.names()[0]


## The preset the current song should use, given its preset mode.
func _resolve_preset() -> Dictionary:
	source = str(music.song_setting("preset_mode", "global"))
	if source == "song":
		var p := presets.get_preset(str(music.song_setting("preset", "")))
		if not p.is_empty():
			return p
		source = "global"
	if source == "auto" and auto_choice != "":
		var p := presets.get_preset(auto_choice)
		if not p.is_empty():
			return p
	return presets.get_preset(global_preset_name())


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
	layers.beatlight.set_mode("beatlight" if float(working.beat_light) > 0.0 and music.app_setting("beat_light", true) else "none")
	layers.beatlight.set_blend(true)
	background.fx = working.background.duplicate()


## Live edit from the Studio: section ("main", "secondary", "atmosphere", "background" or
## "" for top-level keys), key and value. Changes show immediately.
func edit(section: String, key: String, value: Variant) -> void:
	if section == "":
		working[key] = value
	else:
		working[section][key] = value
	if key in ["mode", "additive", "beat_light"] or section == "background":
		_apply_modes()
	working_changed.emit()


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
	preset_changed.emit(working_name)
	show_toast("Saved preset " + working_name)
	return working_name


func duplicate_working() -> String:
	return save_working(presets.unique_name(working_name + " Copy"))


func rename_working(new_name: String) -> bool:
	var old := working_name
	if not presets.rename_preset(old, new_name):
		return false
	working_name = new_name
	working.name = new_name
	if music.app_setting("preset", "") == old:
		music.set_app_setting("preset", new_name)
	preset_changed.emit(working_name)
	return true


func delete_working() -> void:
	presets.delete_preset(working_name)
	apply_preset(presets.get_preset(global_preset_name()))


func restore_builtins() -> void:
	presets.restore_builtins()
	apply_preset(presets.get_preset(global_preset_name()))
	show_toast("Built-in presets restored")


func set_global(preset_name: String) -> void:
	music.set_app_setting("preset", preset_name)
	show_toast("Global preset: " + preset_name)
	if source == "global":
		apply_preset(presets.get_preset(preset_name))


func assign_to_song(preset_name: String) -> void:
	music.set_song_setting("preset", preset_name)
	music.set_song_setting("preset_mode", "song")
	show_toast("Preset for this song: " + preset_name)
	apply_preset(presets.get_preset(preset_name))


func set_song_mode(mode: String) -> void:
	music.set_song_setting("preset_mode", mode if mode != "global" else null)
	auto_choice = ""
	apply_preset(_resolve_preset())


func cycle_preset(step: int) -> void:
	var names := presets.names()
	var i := names.find(working_name)
	preview(names[wrapi(i + step, 0, names.size())])
	show_toast("Preset: " + working_name)


# --- Song changes and automatic atmosphere -------------------------------------------

func _on_track_changed(_index: int) -> void:
	audio.reset_song_stats()
	audio.song_sensitivity = float(music.song_setting("sensitivity", 1.0))
	auto_choice = ""
	auto_reason = ""
	mods_target = {"speed": 1.0, "glow": 1.0, "density": 1.0, "intensity": 1.0, "motion": 1.0}
	var p := _resolve_preset()
	if p.name != working_name or working.is_empty():
		apply_preset(p, not working.is_empty())
	var bg := str(music.song_setting("background", ""))
	background.show_image(music.backgrounds_dir.path_join(bg) if bg != "" and FileAccess.file_exists(music.backgrounds_dir.path_join(bg)) else "")
	_show_notification()


## Derives modifiers and (once per song) a fitting preset from what the song actually
## sounds like so far. Changes are gentle: modifiers ease in, the preset switches once.
func _update_auto() -> void:
	var traits: Dictionary = audio.personality()
	if traits.is_empty():
		return
	var rate: float = traits.onset_rate
	var dyn: float = traits.dynamics
	mods_target = {
		"speed": clampf(0.75 + rate * 0.12, 0.7, 1.4),
		"glow": clampf(0.85 + dyn * 1.5, 0.8, 1.4),
		"density": clampf(0.7 + traits.bass * 1.2, 0.7, 1.4),
		"intensity": clampf(0.85 + dyn * 2.0, 0.8, 1.5),
		"motion": clampf(0.7 + traits.loudness * 0.6, 0.6, 1.3),
	}
	if auto_choice != "":
		return
	if rate < 0.6 and dyn < 0.12:
		auto_choice = "Midnight Aurora"
		auto_reason = "spacious and calm"
	elif traits.bass > 0.42:
		auto_choice = "Stellar Drift"
		auto_reason = "bass-heavy"
	elif rate > 2.0 and traits.treble > 0.22:
		auto_choice = "Neon Pulse"
		auto_reason = "bright and rhythmic"
	elif rate > 1.4:
		auto_choice = "Clockwork Heart"
		auto_reason = "steady rhythm"
	elif traits.loudness < 0.3:
		auto_choice = "Almost Nothing"
		auto_reason = "very quiet"
	else:
		auto_choice = "Seven Souls"
		auto_reason = "warm and melodic"
	if not (auto_choice in presets.names()):
		auto_choice = global_preset_name()
	if source == "auto" and auto_choice != working_name:
		apply_preset(presets.get_preset(auto_choice))


# --- Per frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if working.is_empty():
		return
	_auto_timer += delta
	if _auto_timer > 2.0:
		_auto_timer = 0.0
		if str(music.song_setting("preset_mode", "global")) == "auto":
			_update_auto()
	for k in mods:
		mods[k] = Common.approach(mods[k], mods_target[k] if source == "auto" else 1.0, 0.4, delta)

	# Colours: song colours override the preset's; changes blend over ~1.5 s.
	var pc = music.song_setting("color", null)
	var sc = music.song_setting("color2", null)
	var target_a: Color = pc if pc is Color else Color(working.colors[0])
	var target_b: Color = sc if sc is Color else Color(working.colors[1])
	color_a = color_a.lerp(target_a, 1.0 - exp(-2.0 * delta))
	color_b = color_b.lerp(target_b, 1.0 - exp(-2.0 * delta))
	background.set_palette(color_a, color_b)
	background.motion_scale = float(music.song_setting("bg_motion", 1.0)) * mods.motion

	var s_int := float(music.song_setting("intensity", 1.0))
	var s_glow := float(music.song_setting("glow", 1.0))
	var s_density := float(music.song_setting("particle_density", 1.0))
	for role in ["main", "secondary", "atmosphere"]:
		var cfg: Dictionary = working[role]
		var layer: Control = layers[role]
		layer.opacity = float(cfg.opacity) if role != "secondary" else minf(float(cfg.opacity), 0.8)
		layer.scale_factor = float(cfg.scale)
		layer.intensity = float(cfg.intensity) * s_int * mods.intensity
		layer.speed = float(cfg.speed) * mods.speed
		layer.glow = float(cfg.glow) * s_glow * mods.glow
		layer.trail = float(cfg.trail)
		layer.density = s_density * mods.density * (0.6 if role == "secondary" else 1.0)
		layer.primary = color_a
		layer.secondary = color_b
	var bl: Control = layers.beatlight
	bl.intensity = float(working.beat_light) * float(music.app_setting("beat_light_strength", 1.0))
	bl.primary = color_a

	# The pop-up is for when the panel is hidden; the panel shows the title itself.
	notify_box.visible = not ui.overlay.visible
	_update_cursor(delta)
	if diag.visible:
		_diag_timer += delta
		if _diag_timer > 0.25:
			_diag_timer = 0.0
			_update_diag()


func _update_cursor(delta: float) -> void:
	# Hide the pointer while the interface is hidden and the mouse is still.
	_cursor_idle += delta
	var should_hide: bool = not ui.overlay.visible and _cursor_idle > 2.0
	var want := Input.MOUSE_MODE_HIDDEN if should_hide else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
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
		"preset: %s (%s)%s" % [working_name, source, ("  auto: %s, %s" % [auto_choice, auto_reason]) if auto_choice != "" else ""],
		"song config: %s [%s]" % [music.config_path, music.current_path.get_file()],
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
