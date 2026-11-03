extends Control

const GOLD := Color(0.96, 0.82, 0.52)
const IDLE_TIME := 4.0
const FADE_TIME := 0.8
const SCROLL_SPEED := 70.0
const EQ_LABELS := ["60", "150", "400", "1k", "2.4k", "6k", "15k"]

@onready var music = $"../Music"
@onready var visualizer = $"../Waveform"
@onready var background: TextureRect = $"../Background"
@onready var default_background: Texture2D = background.texture

var overlay := MarginContainer.new()
var title := Label.new()
var scroll_title := Label.new()
var time_label := Label.new()
var seek_bar := HSlider.new()
var playlist := ItemList.new()
var scroll_toggle := CheckButton.new()
var background_select := OptionButton.new()
var color_button := ColorPickerButton.new()
var popups: Array[Popup] = []
var eq_sliders: Array[VSlider] = []
var eq_toggle := CheckButton.new()
var backgrounds: Array[String] = []
var play_button: Button
var lock_button: Button
var idle := 0.0
var seeking := false


func _ready() -> void:
	get_window().min_size = Vector2i(800, 600)
	theme = _make_theme()

	scroll_title.add_theme_font_size_override("font_size", 26)
	scroll_title.add_theme_color_override("font_color", Color(GOLD, 0.8))
	scroll_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	scroll_title.add_theme_constant_override("shadow_offset_y", 2)
	scroll_title.position.y = 28
	add_child(scroll_title)

	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		overlay.add_theme_constant_override("margin_" + side, 20)
	add_child(overlay)
	var panel := PanelContainer.new()
	overlay.add_child(panel)
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

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.focus_mode = FOCUS_NONE
	tabs.get_tab_bar().focus_mode = FOCUS_NONE
	box.add_child(tabs)

	# Playlist
	playlist.name = "Playlist"
	playlist.focus_mode = FOCUS_NONE
	for track in music.tracks:
		playlist.add_item(track.get_file().get_basename())
	playlist.item_clicked.connect(_on_playlist_clicked)
	tabs.add_child(playlist)

	# Visualizer
	var vis := _grid(tabs, "Visualizer")
	var mode_select := OptionButton.new()
	mode_select.add_item("Waveform")
	mode_select.add_item("Square Grid")
	mode_select.item_selected.connect(func(i: int): visualizer.mode = i)
	_row(vis, "Visualizer", mode_select)
	var sensitivity: float = music.app_setting("sensitivity", 100.0)
	visualizer.sensitivity = sensitivity / 100.0
	_row(vis, "Sensitivity", _slider(sensitivity, 200.0, _on_sensitivity))
	_row(vis, "Intensity", _slider(50.0, 100.0, func(v: float): visualizer.intensity_scale = v / 50.0))
	_row(vis, "Hue", _slider(50.0, 100.0, func(v: float): visualizer.hue_sensitivity = v / 100.0))
	scroll_toggle.button_pressed = true
	_row(vis, "Scrolling title", scroll_toggle)

	# Equalizer
	var eq_box := VBoxContainer.new()
	eq_box.name = "Equalizer"
	tabs.add_child(eq_box)
	var bands := HBoxContainer.new()
	bands.size_flags_vertical = SIZE_EXPAND_FILL
	bands.alignment = BoxContainer.ALIGNMENT_CENTER
	bands.add_theme_constant_override("separation", 22)
	eq_box.add_child(bands)
	var gains: Array = music.app_setting("eq_gains", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in 7:
		var column := VBoxContainer.new()
		bands.add_child(column)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.custom_minimum_size.x = 44
		var s := VSlider.new()
		s.min_value = -12.0
		s.max_value = 12.0
		s.step = 0.5
		s.value = gains[i]
		s.size_flags_vertical = SIZE_EXPAND_FILL
		s.size_flags_horizontal = SIZE_SHRINK_CENTER
		s.focus_mode = FOCUS_NONE
		s.value_changed.connect(_on_eq_changed.bind(value))
		eq_sliders.append(s)
		column.add_child(value)
		column.add_child(s)
		var freq := Label.new()
		freq.text = EQ_LABELS[i]
		freq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(freq)
		value.text = "%+.1f" % s.value
	var eq_row := HBoxContainer.new()
	eq_row.alignment = BoxContainer.ALIGNMENT_CENTER
	eq_row.add_theme_constant_override("separation", 12)
	eq_box.add_child(eq_row)
	eq_toggle.text = "EQ On"
	eq_toggle.focus_mode = FOCUS_NONE
	eq_toggle.button_pressed = music.app_setting("eq_enabled", true)
	eq_toggle.toggled.connect(func(on: bool):
		music.set_app_setting("eq_enabled", on)
		music.apply_eq())
	eq_row.add_child(eq_toggle)
	_button(eq_row, "Reset EQ", func():
		for s in eq_sliders:
			s.value = 0.0)

	# Song
	var song := _grid(tabs, "Song")
	backgrounds = music.list_backgrounds()
	background_select.add_item("Default")
	for file in backgrounds:
		background_select.add_item(file.get_basename())
	background_select.item_selected.connect(_on_background_selected)
	_row(song, "Background", background_select)
	var color_row := HBoxContainer.new()
	color_button.edit_alpha = false
	color_button.focus_mode = FOCUS_NONE
	color_button.size_flags_horizontal = SIZE_EXPAND_FILL
	color_button.color_changed.connect(_on_color_changed)
	color_row.add_child(color_button)
	_button(color_row, "Default", _on_color_reset)
	_row(song, "Visualizer colour", color_row)

	popups = [mode_select.get_popup(), background_select.get_popup(), color_button.get_popup()]
	music.track_changed.connect(_on_track_changed)
	_on_track_changed(music.current)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or (event is InputEventKey and event.pressed):
		idle = 0.0
		overlay.modulate.a = 1.0
		overlay.visible = true


func _process(delta: float) -> void:
	idle += delta
	for p in popups:
		if p.visible:
			idle = 0.0
	var target := 1.0 if lock_button.button_pressed or idle < IDLE_TIME else 0.0
	overlay.modulate.a = move_toward(overlay.modulate.a, target, delta / FADE_TIME)
	overlay.visible = overlay.modulate.a > 0.0

	scroll_title.visible = scroll_toggle.button_pressed and not overlay.visible
	if scroll_title.visible:
		scroll_title.position.x -= SCROLL_SPEED * delta
		if scroll_title.position.x < -scroll_title.size.x:
			scroll_title.position.x = size.x

	if not overlay.visible:
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
	title.text = music.tracks[index].get_file().get_basename()
	scroll_title.text = title.text
	scroll_title.reset_size()
	scroll_title.position.x = size.x
	playlist.select(index)
	playlist.ensure_current_is_visible()

	var file_index := backgrounds.find(str(music.song_setting("background", "")))
	background_select.select(file_index + 1)
	_apply_background(file_index)

	var color = music.song_setting("color", false)
	var custom: bool = color is Color
	color_button.color = color if custom else visualizer.GOLD
	visualizer.set_base_color(color_button.color, custom)


func _apply_background(file_index: int) -> void:
	var image: Image = null
	if file_index >= 0:
		image = Image.load_from_file(music.backgrounds_dir.path_join(backgrounds[file_index]))
	background.texture = ImageTexture.create_from_image(image) if image else default_background


func _on_background_selected(i: int) -> void:
	music.set_song_setting("background", backgrounds[i - 1] if i > 0 else null)
	_apply_background(i - 1)


func _on_color_changed(color: Color) -> void:
	music.set_song_setting("color", color)
	visualizer.set_base_color(color, true)


func _on_color_reset() -> void:
	music.set_song_setting("color", null)
	color_button.color = visualizer.GOLD
	visualizer.set_base_color(visualizer.GOLD, false)


func _on_sensitivity(v: float) -> void:
	visualizer.sensitivity = v / 100.0
	music.set_app_setting("sensitivity", v)


func _on_eq_changed(v: float, value_label: Label) -> void:
	value_label.text = "%+.1f" % v
	var gains := []
	for s in eq_sliders:
		gains.append(s.value)
	music.set_app_setting("eq_gains", gains)
	music.apply_eq()


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


func _slider(value: float, max_value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.max_value = max_value
	s.value = value
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.focus_mode = FOCUS_NONE
	s.value_changed.connect(on_change)
	return s


func _grid(tabs: TabContainer, tab_name: String) -> GridContainer:
	var margin := MarginContainer.new()
	margin.name = tab_name
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	tabs.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	margin.add_child(grid)
	return grid


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	control.focus_mode = FOCUS_NONE
	grid.add_child(control)


func _time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.05, 0.04, 0.66)
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
	track.content_margin_left = 2
	track.content_margin_right = 2
	var fill := track.duplicate()
	fill.bg_color = Color(GOLD, 0.65)
	for slider in ["HSlider", "VSlider"]:
		th.set_stylebox("slider", slider, track)
		th.set_stylebox("grabber_area", slider, fill)
		th.set_stylebox("grabber_area_highlight", slider, fill)
		th.set_icon("grabber", slider, _dot(6, GOLD))
		th.set_icon("grabber_highlight", slider, _dot(7, GOLD))

	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0.18)
	inner.set_corner_radius_all(6)
	inner.set_content_margin_all(6)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(GOLD, 0.16)
	selected.set_corner_radius_all(4)
	var hovered := selected.duplicate()
	hovered.bg_color = Color(GOLD, 0.08)
	th.set_stylebox("panel", "ItemList", inner)
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("selected", "ItemList", selected)
	th.set_stylebox("selected_focus", "ItemList", selected)
	th.set_stylebox("hovered", "ItemList", hovered)
	th.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", Color(GOLD, 0.7))
	th.set_color("font_hovered_color", "ItemList", GOLD)
	th.set_color("font_selected_color", "ItemList", GOLD)

	th.set_stylebox("panel", "TabContainer", inner)
	th.set_stylebox("tab_selected", "TabContainer", selected)
	th.set_stylebox("tab_hovered", "TabContainer", hovered)
	var unselected := StyleBoxEmpty.new()
	th.set_stylebox("tab_unselected", "TabContainer", unselected)
	th.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	for s in [selected, hovered, unselected]:
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 4
		s.content_margin_bottom = 4
	th.set_color("font_selected_color", "TabContainer", GOLD)
	th.set_color("font_hovered_color", "TabContainer", GOLD)
	th.set_color("font_unselected_color", "TabContainer", Color(GOLD, 0.6))
	return th


func _dot(radius: int, color: Color) -> ImageTexture:
	var img := Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	for x in radius * 2:
		for y in radius * 2:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			img.set_pixel(x, y, Color(color, clampf(radius - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
