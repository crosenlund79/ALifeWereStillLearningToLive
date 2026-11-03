extends Control

const GOLD := Color(0.96, 0.82, 0.52)
const IDLE_TIME := 4.0
const FADE_TIME := 0.8

@onready var music = $"../Music"
@onready var waveform = $"../Waveform"

var panel := PanelContainer.new()
var title := Label.new()
var time_label := Label.new()
var seek_bar := HSlider.new()
var playlist := ItemList.new()
var play_button: Button
var lock_button: Button
var idle := 0.0
var seeking := false


func _ready() -> void:
	theme = _make_theme()

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)
	panel.custom_minimum_size.x = 660
	panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	column.add_child(panel)
	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size.y = 28
	bottom_gap.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(bottom_gap)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var seek_row := HBoxContainer.new()
	seek_row.add_theme_constant_override("separation", 12)
	box.add_child(seek_row)
	seek_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	seek_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	seek_bar.step = 0.1
	seek_bar.focus_mode = FOCUS_NONE
	seek_bar.drag_started.connect(_on_seek_started)
	seek_bar.drag_ended.connect(_on_seek_ended)
	seek_row.add_child(seek_bar)
	time_label.custom_minimum_size.x = 90
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seek_row.add_child(time_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_button(buttons, "Prev", music.previous_track)
	_button(buttons, "-5s", music.seek_by.bind(-music.SEEK_STEP))
	play_button = _button(buttons, "Pause", music.toggle_pause)
	_button(buttons, "Restart", music.restart)
	_button(buttons, "+5s", music.seek_by.bind(music.SEEK_STEP))
	_button(buttons, "Next", music.next_track)
	_button(buttons, "Fullscreen", music.toggle_fullscreen)
	lock_button = _button(buttons, "Lock", _on_lock)
	lock_button.toggle_mode = true

	playlist.custom_minimum_size.y = 110
	playlist.focus_mode = FOCUS_NONE
	for track in music.tracks:
		playlist.add_item(track.get_basename())
	playlist.item_clicked.connect(_on_playlist_clicked)
	box.add_child(playlist)

	var effects := HBoxContainer.new()
	effects.add_theme_constant_override("separation", 12)
	box.add_child(effects)
	_slider(effects, "Intensity", 50.0, func(v: float): waveform.intensity_scale = v / 50.0)
	_slider(effects, "Hue", 50.0, func(v: float): waveform.hue_sensitivity = v / 100.0)

	music.track_changed.connect(_on_track_changed)
	_on_track_changed(music.current)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or (event is InputEventKey and event.pressed):
		idle = 0.0
		panel.modulate.a = 1.0
		panel.visible = true


func _process(delta: float) -> void:
	idle += delta
	var target := 1.0 if lock_button.button_pressed or idle < IDLE_TIME else 0.0
	panel.modulate.a = move_toward(panel.modulate.a, target, delta / FADE_TIME)
	panel.visible = panel.modulate.a > 0.0
	if not panel.visible:
		return
	var length: float = music.stream.get_length() if music.stream else 0.0
	seek_bar.max_value = maxf(length, 0.1)
	if not seeking:
		seek_bar.value = music.get_playback_position()
	time_label.text = "%s / %s" % [_time(seek_bar.value), _time(length)]
	play_button.text = "Play" if music.stream_paused else "Pause"


func _on_track_changed(index: int) -> void:
	if music.tracks.is_empty():
		title.text = "No tracks in music/"
		return
	title.text = music.tracks[index].get_basename()
	playlist.select(index)
	playlist.ensure_current_is_visible()


func _on_playlist_clicked(index: int, _pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		music.play_track(index)


func _on_seek_started() -> void:
	seeking = true


func _on_seek_ended(_changed: bool) -> void:
	seeking = false
	music.seek_to(seek_bar.value)


func _on_lock() -> void:
	lock_button.text = "Locked" if lock_button.button_pressed else "Lock"


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE  # Keep Space/Enter/arrows for the keyboard controls.
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _slider(parent: Control, text: String, value: float, on_change: Callable) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	var s := HSlider.new()
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.focus_mode = FOCUS_NONE
	s.value = value
	s.value_changed.connect(on_change)
	parent.add_child(s)


func _time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.05, 0.04, 0.62)
	bg.border_color = Color(GOLD, 0.22)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(16)
	th.set_stylebox("panel", "PanelContainer", bg)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(GOLD, {"normal": 0.06, "hover": 0.14, "pressed": 0.24, "hover_pressed": 0.28, "disabled": 0.03}[state])
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		th.set_stylebox(state, "Button", sb)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", GOLD)

	th.set_color("font_color", "Label", GOLD)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(GOLD, 0.18)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := track.duplicate()
	fill.bg_color = Color(GOLD, 0.65)
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _dot(6, GOLD))
	th.set_icon("grabber_highlight", "HSlider", _dot(7, GOLD))

	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0, 0, 0, 0.18)
	list_bg.set_corner_radius_all(6)
	list_bg.set_content_margin_all(6)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(GOLD, 0.16)
	selected.set_corner_radius_all(4)
	var hovered := selected.duplicate()
	hovered.bg_color = Color(GOLD, 0.08)
	th.set_stylebox("panel", "ItemList", list_bg)
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("selected", "ItemList", selected)
	th.set_stylebox("selected_focus", "ItemList", selected)
	th.set_stylebox("hovered", "ItemList", hovered)
	th.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", Color(GOLD, 0.7))
	th.set_color("font_hovered_color", "ItemList", GOLD)
	th.set_color("font_selected_color", "ItemList", GOLD)
	return th


func _dot(radius: int, color: Color) -> ImageTexture:
	var img := Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	for x in radius * 2:
		for y in radius * 2:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			img.set_pixel(x, y, Color(color, clampf(radius - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
