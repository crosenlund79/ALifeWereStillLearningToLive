extends Control
## TinserBox overlay: moods (music + look), Visualizer Studio, equalizer, mood look and app
## settings, plus the transport bar. Fades after inactivity; Esc hides it until the next
## activity; H hides it until H is pressed again (saved).

const Common := preload("res://vis/common.gd")
const Layer := preload("res://vis/visual_layer.gd")
const Presets := preload("res://presets.gd")
const GOLD := Color(0.96, 0.82, 0.52)
const IDLE_TIME := 4.0
const FADE_TIME := 0.8
const SCROLL_SPEED := 70.0
const LIGHT_FONT := preload("res://Font/LEMONMILK-Light.otf")
const BOLD_FONT := preload("res://Font/LEMONMILK-Bold.otf")
const EQ_LABELS := ["60", "150", "400", "1k", "2.4k", "6k", "15k"]
const SORT_LABELS := ["Name A-Z", "Name Z-A", "Artist", "Recently changed"]
const SONG_MODES := ["global", "song", "auto"]

@onready var music = $"../Music"
@onready var director = $"../Director"
@onready var audio = $"../Audio"

var overlay := MarginContainer.new()
var title := Label.new()
var scroll_title := Label.new()
var time_label := Label.new()
var seek_bar := HSlider.new()
var playlist := ItemList.new()
var search := LineEdit.new()
var sort_select := OptionButton.new()
var context_menu := PopupMenu.new()
var file_dialog := FileDialog.new()
var visible_rows: Array[int] = []
var context_row := -1
var mood_list := ItemList.new()
var mood_name_edit := LineEdit.new()
var moods_menu := PopupMenu.new()  # Checkable mood tags for the selected songs.
var look_box: VBoxContainer
var look_for := "\u0001"
var _thumbs := {}
# Mini player (Ctrl+M): compact, borderless, always on top. Never restored at launch.
const MINI_SIZE := Vector2i(400, 300)
var mini := false
var mini_panel := PanelContainer.new()
var mini_title := Label.new()
var mini_controls := HBoxContainer.new()
var mini_buttons: Array[Button] = []
var mini_volume: HSlider
var _saved_window := {}
var _drag_from := Vector2i(-1, -1)
var _drag_window := Vector2i.ZERO
var scroll_toggle := CheckButton.new()
var preset_select := OptionButton.new()
var preset_name_edit := LineEdit.new()
var popups: Array[Popup] = []
var eq_sliders: Array[VSlider] = []
var eq_toggle := CheckButton.new()
var studio_controls := {}  # "section/key" -> Control
var mode_grid: GridContainer  # Settings specific to the main layer's visualizer.
var mode_grid_for := ""
var main_color_button := ColorPickerButton.new()
var second_color_button := ColorPickerButton.new()
var palette_buttons: Array[ColorPickerButton] = []
var rec_button: Button
var rec_status := Label.new()
var rec_name := LineEdit.new()
var rec_dir_label := Label.new()
var play_button: Button
var lock_button: Button
var shuffle_button: Button
var repeat_button: Button
var mute_button: Button
var volume_slider: HSlider
var volume_label := Label.new()
var frame_toggle := CheckButton.new()
var shot_dir_label := Label.new()
var source_select := OptionButton.new()
var player_only: Array[Control] = []  # Controls hidden while visualizing system audio.
var frame_hidden := false
var syncing := false
var hidden_by_user := false
var hide_mode := false  # H: interface stays hidden until H is pressed again.
var idle := 0.0
var seeking := false


func _ready() -> void:
	get_window().min_size = Vector2i(800, 600)
	theme = _make_theme()

	scroll_title.add_theme_font_size_override("font_size", 26)
	scroll_title.add_theme_font_override("font", BOLD_FONT)
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

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.focus_mode = FOCUS_NONE
	tabs.get_tab_bar().focus_mode = FOCUS_NONE
	box.add_child(tabs)
	_build_moods_tab(tabs)
	_build_mood_look_tab(tabs)
	_build_studio_tab(tabs)
	_build_eq_tab(tabs)
	_build_settings_tab(tabs)

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_font_override("font", BOLD_FONT)
	box.add_child(title)
	_build_transport(box)
	_build_mini()

	add_child(context_menu)
	context_menu.add_item("Play now", 0)
	context_menu.add_item("Queue next", 1)
	context_menu.add_item("Remove", 2)
	moods_menu.name = "Moods"
	moods_menu.hide_on_checkable_item_selection = false
	moods_menu.id_pressed.connect(_on_mood_tag)
	context_menu.add_child(moods_menu)
	context_menu.add_submenu_item("Moods", "Moods", 3)
	context_menu.add_item("Clear queue", 4)
	context_menu.id_pressed.connect(_on_context)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.dir_selected.connect(_on_dir_selected)
	file_dialog.files_selected.connect(func(files: PackedStringArray): music.add_paths(files))
	add_child(file_dialog)

	music.track_changed.connect(_on_track_changed)
	music.playlist_changed.connect(_refresh_playlist)
	music.moods_changed.connect(_refresh_moods)
	director.preset_changed.connect(func(_n): _sync_studio())
	director.working_changed.connect(_sync_studio)
	music.source_changed.connect(_update_source_ui)
	_refresh_playlist()
	_on_track_changed(music.current)
	_sync_studio()
	_update_source_ui()
	if music.app_setting("hide_mode", false):
		toggle_hide_mode()


# --- Tabs ---------------------------------------------------------------------------

## Moods: the mood list (left) and the songs of the browsed mood or All Music (right).
func _build_moods_tab(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Moods"
	tab.add_theme_constant_override("separation", 8)
	tabs.add_child(tab)
	var split := HBoxContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	tab.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 215
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	mood_list.focus_mode = FOCUS_NONE
	mood_list.size_flags_vertical = SIZE_EXPAND_FILL
	mood_list.fixed_icon_size = Vector2i(34, 20)
	mood_list.tooltip_text = "Click a mood to browse it (the playing song continues). Double-click, or Play this mood, to start it. Drop songs on a mood to add them; drag moods to reorder."
	mood_list.item_selected.connect(func(i: int):
		if not syncing:
			music.set_active_mood(str(mood_list.get_item_metadata(i))))
	mood_list.item_activated.connect(func(i: int):
		music.set_active_mood(str(mood_list.get_item_metadata(i)))
		music.play_mood())
	mood_list.set_drag_forwarding(_mood_drag, _mood_can_drop, _mood_drop)
	left.add_child(mood_list)
	mood_name_edit.placeholder_text = "Mood name"
	left.add_child(mood_name_edit)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 4)
	left.add_child(mrow)
	_button(mrow, "New", _on_new_mood, "Create a mood with the name typed above")
	_button(mrow, "Rename", _on_rename_mood, "Rename the selected mood to the name typed above")
	_button(mrow, "Delete", _on_delete_mood, "Delete the selected mood (its songs stay in All Music and on disk)")
	var play_mood := _button(left, "Play this mood", music.play_mood, "Start playing the selected mood with its look")
	play_mood.size_flags_horizontal = SIZE_EXPAND_FILL

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	right.add_child(tools)
	search.placeholder_text = "Search"
	search.size_flags_horizontal = SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _refresh_playlist())
	tools.add_child(search)
	for label in SORT_LABELS:
		sort_select.add_item(label)
	sort_select.select(maxi(music.SORTS.find(music.sort_mode), 0))
	sort_select.focus_mode = FOCUS_NONE
	sort_select.item_selected.connect(func(i: int): music.set_sort(music.SORTS[i]))
	popups.append(sort_select.get_popup())
	tools.add_child(sort_select)
	_button(tools, "+ Folder", _open_dialog.bind(FileDialog.FILE_MODE_OPEN_DIR), "Add a folder of music (scanned in the background). You can also drag folders or files onto the window.")
	_button(tools, "+ Files", _open_dialog.bind(FileDialog.FILE_MODE_OPEN_FILES), "Add music files")
	playlist.focus_mode = FOCUS_NONE
	playlist.size_flags_vertical = SIZE_EXPAND_FILL
	playlist.select_mode = ItemList.SELECT_MULTI
	playlist.item_clicked.connect(_on_playlist_clicked)
	playlist.item_activated.connect(func(row: int):
		if row < visible_rows.size():
			music.play_track(visible_rows[row]))
	playlist.tooltip_text = "Double-click to play. Ctrl/Shift-click to select several. Drag songs onto a mood to add them, or within a mood to reorder. Right-click: play, queue, moods, remove."
	playlist.set_drag_forwarding(_playlist_drag, _playlist_can_drop, _playlist_drop)
	right.add_child(playlist)

	var delay_row := HBoxContainer.new()
	delay_row.add_theme_constant_override("separation", 12)
	tab.add_child(delay_row)
	var delay_title := Label.new()
	delay_title.text = "Between songs delay"
	delay_row.add_child(delay_title)
	var delay_value := Label.new()
	delay_value.custom_minimum_size.x = 44
	var delay_slider := _slider(music.song_delay, 30.0, func(v: float):
		music.set_song_delay(int(v))
		delay_value.text = "%d s" % int(v))
	delay_slider.step = 1.0
	delay_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	delay_slider.tooltip_text = "Pause after a song finishes before the next one starts (0-30 s)"
	delay_row.add_child(delay_slider)
	delay_value.text = "%d s" % music.song_delay
	delay_row.add_child(delay_value)


func _build_studio_tab(tabs: TabContainer) -> void:
	var col := _scroll_tab(tabs, "Visualizer")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	col.add_child(row1)
	preset_select.size_flags_horizontal = SIZE_EXPAND_FILL
	preset_select.focus_mode = FOCUS_NONE
	preset_select.tooltip_text = "Preview a preset (keys 1-9, [ and ] also switch presets)"
	preset_select.item_selected.connect(func(i: int): director.preview(str(preset_select.get_item_metadata(i))))
	row1.add_child(preset_select)
	_button(row1, "Save", func(): director.save_working(), "Save changes to this preset")
	_button(row1, "Duplicate", func(): director.duplicate_working(), "Save a copy of the current settings")
	_button(row1, "Delete", func(): director.delete_working(), "Delete this preset (built-ins can be restored)")
	_button(row1, "Reset", func(): director.restore_defaults(), "Discard unsaved changes")

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	col.add_child(row2)
	preset_name_edit.placeholder_text = "New preset name"
	preset_name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	row2.add_child(preset_name_edit)
	_button(row2, "Save as", _on_save_as, "Save the current settings as a new preset")
	_button(row2, "Rename", _on_rename, "Rename this preset (your own presets only)")
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	col.add_child(row3)
	_button(row3, "Use globally", func(): director.set_global(director.working_name), "Use this preset for all songs that follow the global preset")
	_button(row3, "Add to mood", _add_preset_to_mood, "Add this preset to the mood selected in the Moods tab")
	_button(row3, "Restore built-ins", func(): director.restore_builtins(), "Bring back the original built-in presets")

	var modes := Layer.MODE_NAMES
	_build_dancer_section(col)

	_section(col, "Main layer")
	var g := _grid4(col)
	var main_modes := {"none": "None (dancer only)"}
	main_modes.merge(modes)
	_studio_option(g, "Visualizer", "main", "mode", main_modes)
	_studio_slider(g, "Opacity", "main", "opacity", 0.0, 1.0)
	_studio_slider(g, "Scale", "main", "scale", 0.5, 1.5)
	_studio_slider(g, "Intensity", "main", "intensity", 0.0, 2.0)
	_studio_slider(g, "Motion speed", "main", "speed", 0.2, 2.0)
	_studio_slider(g, "Glow", "main", "glow", 0.0, 2.0)
	_studio_check(g, "Light blend", "main", "additive", "Additive blending: overlapping light adds up")
	mode_grid = _grid4(col)  # Filled per visualizer in _rebuild_mode_grid().

	_section(col, "Colours")
	var cg := _grid4(col)
	_label(cg, "Main colour")
	_fill(cg, _studio_color(main_color_button, -1))
	_label(cg, "Second colour")
	_fill(cg, _studio_color(second_color_button, -2))
	var pal_row := HBoxContainer.new()
	pal_row.add_theme_constant_override("separation", 4)
	col.add_child(pal_row)
	var pal_label := Label.new()
	pal_label.text = "Element colours"
	pal_label.custom_minimum_size.x = 120
	pal_label.add_theme_color_override("font_color", Color(GOLD, 0.8))
	pal_label.tooltip_text = "Lines, spirits, rings, ribbons, curtains, grid and block colours (1 = first / lowest)"
	pal_row.add_child(pal_label)
	for k in 7:
		var b := ColorPickerButton.new()
		b.custom_minimum_size = Vector2(30, 24)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		pal_row.add_child(_studio_color(b, k))
		palette_buttons.append(b)
	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 6)
	col.add_child(col_row)
	_button(col_row, "Reset colours", _reset_colours, "Restore this preset's original colours")
	_button(col_row, "Use for this mood", _mood_colours.bind(true), "The mood selected in the Moods tab keeps these colours whatever preset it shows")

	_section(col, "Second layer")
	g = _grid4(col)
	var with_none := {"none": "None"}
	with_none.merge(modes)
	_studio_option(g, "Visualizer", "secondary", "mode", with_none)
	_studio_slider(g, "Opacity", "secondary", "opacity", 0.0, 0.8)
	_studio_slider(g, "Scale", "secondary", "scale", 0.5, 1.5)
	_studio_slider(g, "Intensity", "secondary", "intensity", 0.0, 2.0)

	_section(col, "Atmosphere")
	g = _grid4(col)
	_studio_option(g, "Effect", "atmosphere", "mode", Layer.ATMOSPHERE_NAMES)
	_studio_slider(g, "Opacity", "atmosphere", "opacity", 0.0, 1.0)
	_studio_slider(g, "Beat light", "", "beat_light", 0.0, 1.0)

	_section(col, "Background")
	g = _grid4(col)
	for item in [["Ken Burns", "kenburns"], ["Parallax", "parallax"], ["Breathing", "breathing"], ["Vignette", "vignette"],
			["Dimming", "dim"], ["Colour wash", "wash"], ["Blur", "blur"], ["Bloom", "bloom"], ["Shimmer", "shimmer"]]:
		_studio_slider(g, item[0], "background", item[1], 0.0, 1.0)

	_section(col, "Audio response")
	g = _grid4(col)
	_label(g, "Sensitivity")
	var sens := _slider(float(music.app_setting("sensitivity", 100.0)), 200.0, func(v: float):
		audio.sensitivity = v / 100.0
		music.set_app_setting("sensitivity", v))
	sens.tooltip_text = "How easily visuals react to audio (0-200%)"
	_fill(g, sens)
	_label(g, "Adaptive")
	var adaptive := CheckButton.new()
	adaptive.button_pressed = audio.adaptive
	adaptive.tooltip_text = "Adaptive sensitivity: follows each song's level so quiet recordings still move. Off: fixed reference, Sensitivity only."
	adaptive.toggled.connect(func(on: bool):
		audio.adaptive = on
		music.set_app_setting("adaptive", on))
	_fill(g, adaptive)


## Dancing companion: independent of the visualizer and its presets (saved app-wide).
func _build_dancer_section(col: VBoxContainer) -> void:
	_section(col, "Dancing companion (All Music; moods choose their own)")
	var g := _grid4(col)
	_label(g, "Dancer")
	var on := CheckButton.new()
	on.button_pressed = music.app_setting("dancer_enabled", false)
	on.tooltip_text = "Show a dancing companion in front of the visualizer (or alone, with Visualizer: None)"
	on.toggled.connect(func(v: bool):
		music.set_app_setting("dancer_enabled", v)
		director.apply_dancer_settings())
	_fill(g, on)
	_label(g, "Character")
	var pick := OptionButton.new()
	var names: Array = director.dancer.list_characters()
	for n in names:
		pick.add_item(n)
	pick.select(maxi(names.find(str(music.app_setting("dancer_character", "Aria"))), 0))
	pick.tooltip_text = "Built-in companions, plus any dancers you put in the dancers folder (see README.txt there)"
	pick.item_selected.connect(func(i: int):
		music.set_app_setting("dancer_character", pick.get_item_text(i))
		director.apply_dancer_settings())
	_fill(g, pick)
	_label(g, "Personality")
	var pers := OptionButton.new()
	for n in director.dancer.PERSONALITIES:
		pers.add_item(n.capitalize())
	pers.select(maxi(director.dancer.PERSONALITIES.find(str(music.app_setting("dancer_personality", "playful"))), 0))
	pers.item_selected.connect(func(i: int):
		music.set_app_setting("dancer_personality", director.dancer.PERSONALITIES[i])
		director.apply_dancer_settings())
	_fill(g, pers)
	_label(g, "Lighting")
	var light := _slider(float(music.app_setting("dancer_light", 60.0)), 100.0, func(v: float):
		music.set_app_setting("dancer_light", v)
		director.dancer.light_strength = v / 100.0)
	light.tooltip_text = "How strongly the visualizer's colours light the dancer (0-100%)"
	_fill(g, light)
	_label(g, "Size")
	var dsize := _slider(float(music.app_setting("dancer_size", 1.0)), 1.6, func(v: float):
		music.set_app_setting("dancer_size", v)
		director.dancer.size_mul = v)
	dsize.min_value = 0.5
	dsize.step = 0.05
	_fill(g, dsize)


func _build_eq_tab(tabs: TabContainer) -> void:
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


func _build_mood_look_tab(tabs: TabContainer) -> void:
	look_box = _scroll_tab(tabs, "Mood Look")


## The browsed mood's look: presets (and variation), backgrounds, colours, energy, dancer.
## Rebuilt when another mood is selected.
func _rebuild_mood_look(force := false) -> void:
	var mood_name: String = music.active_mood
	if mood_name == look_for and not force:
		return
	look_for = mood_name
	for c in look_box.find_children("*", "", true, false):
		if c is OptionButton or c is ColorPickerButton:
			popups.erase(c.get_popup())
	for c in look_box.get_children():
		c.queue_free()
	if mood_name == music.ALL_MUSIC:
		var hint := Label.new()
		hint.text = "All Music has no mood look.\nSelect or create a mood in the Moods tab to give it presets,\ncolours, backgrounds and a dancing companion.\nSongs played from All Music use the global preset."
		look_box.add_child(hint)
		return
	var m: Dictionary = music.mood(mood_name)
	_section(look_box, "Look of " + mood_name)

	var pg := GridContainer.new()
	pg.columns = 3
	pg.add_theme_constant_override("h_separation", 12)
	look_box.add_child(pg)
	for pname in director.presets.names():
		var cb := CheckBox.new()
		cb.text = pname
		cb.focus_mode = FOCUS_NONE
		cb.button_pressed = pname in m.presets
		cb.toggled.connect(_on_mood_preset_toggled.bind(pname))
		pg.add_child(cb)
	var vg := _grid4(look_box)
	_label(vg, "Variation")
	var variation := OptionButton.new()
	variation.add_item("Auto variation")
	variation.add_item("Fixed")
	variation.select(1 if m.variation == "fixed" else 0)
	variation.tooltip_text = "Auto variation: a different preset from this mood for each song. Fixed: always the preset on the right."
	variation.item_selected.connect(func(i: int): music.set_mood_value(mood_name, "variation", ["auto", "fixed"][i]))
	_fill(vg, variation)
	_label(vg, "Fixed preset")
	var fixed := OptionButton.new()
	for pname in m.presets:
		fixed.add_item(pname)
	fixed.select(maxi(Array(m.presets).find(m.preset), 0))
	fixed.item_selected.connect(func(i: int): music.set_mood_value(mood_name, "preset", fixed.get_item_text(i)))
	_fill(vg, fixed)
	var save_row := HBoxContainer.new()
	look_box.add_child(save_row)
	_button(save_row, "Save current look to this mood", _save_look_to_mood, "Save what is on screen now (including Studio changes) as a preset of this mood")

	_section(look_box, "Backgrounds (rotate per song)")
	var bg_grid := GridContainer.new()
	bg_grid.columns = 3
	bg_grid.add_theme_constant_override("h_separation", 12)
	look_box.add_child(bg_grid)
	var bgs: Array = music.list_backgrounds()
	if bgs.is_empty():
		var none := Label.new()
		none.text = "No images in the backgrounds folder: the forest is used."
		bg_grid.add_child(none)
	for f in bgs:
		var cb := CheckBox.new()
		cb.text = f.get_basename()
		cb.focus_mode = FOCUS_NONE
		cb.button_pressed = f in m.backgrounds
		cb.toggled.connect(_on_mood_bg_toggled.bind(f))
		bg_grid.add_child(cb)

	_section(look_box, "Colours")
	var cg := _grid4(look_box)
	for idx in 2:
		_label(cg, ["Main colour", "Second colour"][idx])
		var picker := ColorPickerButton.new()
		picker.edit_alpha = false
		picker.focus_mode = FOCUS_NONE
		picker.custom_minimum_size.y = 24
		picker.color = Color(m.colors[idx]) if m.colors.size() >= 2 else Color(director.working.colors[idx])
		picker.color_changed.connect(_on_mood_color.bind(idx))
		popups.append(picker.get_popup())
		_fill(cg, picker)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	look_box.add_child(crow)
	_button(crow, "Use Studio colours", _mood_colours.bind(true), "Copy the Studio's main, second and element colours into this mood")
	_button(crow, "Use preset colours", _mood_colours.bind(false), "Let each preset bring its own colours")

	_section(look_box, "Energy and companion")
	var eg := _grid4(look_box)
	for item in [["Sensitivity", "sensitivity", 0.5, 1.5], ["Intensity", "intensity", 0.5, 1.5], ["Background motion", "motion", 0.0, 1.5]]:
		_label(eg, item[0])
		var sl := _slider(float(m[item[1]]), item[3], func(v: float): music.set_mood_value(mood_name, item[1], v))
		sl.min_value = item[2]
		sl.step = 0.05
		sl.value = float(m[item[1]])
		_fill(eg, sl)
	_label(eg, "Dancer")
	var dancer_pick := OptionButton.new()
	var names: Array = ["None"] + director.dancer.list_characters()
	for n in names:
		dancer_pick.add_item(n)
	dancer_pick.select(maxi(names.find(m.dancer), 0) if m.dancer != "" else 0)
	dancer_pick.item_selected.connect(func(i: int): music.set_mood_value(mood_name, "dancer", "" if i == 0 else dancer_pick.get_item_text(i)))
	_fill(eg, dancer_pick)
	_label(eg, "Personality")
	var pers := OptionButton.new()
	for n in director.dancer.PERSONALITIES:
		pers.add_item(n.capitalize())
	pers.select(maxi(director.dancer.PERSONALITIES.find(m.personality), 0))
	pers.item_selected.connect(func(i: int): music.set_mood_value(mood_name, "personality", director.dancer.PERSONALITIES[i]))
	_fill(eg, pers)


func _on_mood_preset_toggled(on: bool, pname: String) -> void:
	var m: Dictionary = music.mood(music.active_mood)
	var list: Array = Array(m.presets).duplicate()
	if on and not (pname in list):
		list.append(pname)
	elif not on:
		list.erase(pname)
	music.set_mood_value(music.active_mood, "presets", list)
	_rebuild_mood_look(true)


func _on_mood_bg_toggled(on: bool, file: String) -> void:
	var list: Array = Array(music.mood(music.active_mood).backgrounds).duplicate()
	if on and not (file in list):
		list.append(file)
	elif not on:
		list.erase(file)
	music.set_mood_value(music.active_mood, "backgrounds", list)


func _on_mood_color(c: Color, idx: int) -> void:
	var m: Dictionary = music.mood(music.active_mood)
	var cols: Array = Array(m.colors).duplicate() if m.colors.size() >= 2 else Array(director.working.colors).duplicate()
	cols[idx] = "#" + c.to_html(false)
	music.set_mood_value(music.active_mood, "colors", cols)


func _mood_colours(use_studio: bool) -> void:
	if music.active_mood == music.ALL_MUSIC:
		return
	music.set_mood_value(music.active_mood, "colors", Array(director.working.colors).duplicate() if use_studio else [])
	music.set_mood_value(music.active_mood, "palette", Array(director.working.palette).duplicate() if use_studio else [])
	_rebuild_mood_look(true)


## Saves the look on screen as a preset that belongs to the browsed mood.
func _save_look_to_mood() -> void:
	var mood_name: String = music.active_mood
	if mood_name == music.ALL_MUSIC:
		return
	var saved: String = director.save_working(director.presets.unique_name(mood_name + " look"))
	var list: Array = Array(music.mood(mood_name).presets).duplicate()
	list.append(saved)
	music.set_mood_value(mood_name, "presets", list)
	_rebuild_mood_look(true)


func _build_settings_tab(tabs: TabContainer) -> void:
	var col := _scroll_tab(tabs, "Settings")
	var g := _grid4(col)
	_label(g, "Audio source")
	source_select.add_item("TinserBox player")
	source_select.add_item("System audio")
	source_select.tooltip_text = "System audio: visualize whatever Windows is playing (Spotify, a browser, games). Control playback in that app; the visuals follow."
	source_select.item_selected.connect(func(i: int):
		if not music.set_source(["player", "system"][i]):
			source_select.select(0))
	_fill(g, source_select)
	_label(g, "Quality")
	var quality := OptionButton.new()
	for q in ["Performance", "Balanced", "Quality"]:
		quality.add_item(q)
	quality.select(Common.quality)
	quality.tooltip_text = "Particle counts, trail length, glow and background effects"
	quality.item_selected.connect(func(i: int):
		Common.quality = i as Common.Quality
		music.set_app_setting("quality", i))
	_fill(g, quality)
	_setting_check(g, "Song pop-up", "track_notification", true, "Briefly show the title and artist when a song starts")
	_setting_check(g, "Pop-up in H mode", "notify_in_immersive", false, "Also show the track notification while the interface is hidden with H")
	_label(g, "Scrolling title")
	scroll_toggle.button_pressed = music.app_setting("scrolling_title", true)
	scroll_toggle.toggled.connect(func(on: bool): music.set_app_setting("scrolling_title", on))
	_fill(g, scroll_toggle)
	_label(g, "Hide frame")
	frame_toggle.button_pressed = music.app_setting("hide_frame", false)
	frame_toggle.tooltip_text = "Hide the window title bar and borders while the interface is hidden"
	frame_toggle.toggled.connect(func(on: bool): music.set_app_setting("hide_frame", on))
	_fill(g, frame_toggle)
	_setting_check(g, "Beat light", "beat_light", true, "Gentle light pulse on strong beats (never strobes)", func(_on): director.apply_preset(director.working, false))
	_label(g, "Beat strength")
	var bl := _slider(float(music.app_setting("beat_light_strength", 1.0)) * 100.0, 150.0, func(v: float): music.set_app_setting("beat_light_strength", v / 100.0))
	_fill(g, bl)
	_label(g, "Fallback image")
	var fallback := OptionButton.new()
	fallback.add_item("Forest")
	fallback.add_item("Procedural")
	fallback.select(1 if music.app_setting("fallback_procedural", false) else 0)
	fallback.item_selected.connect(func(i: int):
		music.set_app_setting("fallback_procedural", i == 1)
		director.background.fallback_procedural = i == 1
		director.background.current_key = ""
		director._on_track_changed(music.current))
	_fill(g, fallback)
	_setting_check(g, "Shots hide UI", "screenshot_hide_ui", true, "Leave the interface out of screenshots")

	_section(col, "Screenshots")
	var shot_row := HBoxContainer.new()
	shot_row.add_theme_constant_override("separation", 8)
	col.add_child(shot_row)
	shot_dir_label.size_flags_horizontal = SIZE_EXPAND_FILL
	shot_dir_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shot_dir_label.text = director.screenshot_dir()
	shot_row.add_child(shot_dir_label)
	_button(shot_row, "Choose folder", _choose_screenshot_dir, "Where screenshots are saved")
	_button(shot_row, "Take screenshot", func(): director.take_screenshot(), "Save a PNG of the visualizer (%s)" % music.app_setting("screenshot_key", "F12"))
	_button(shot_row, "Diagnostics", _toggle_diag, "Show or hide the diagnostics overlay (F3)")

	_section(col, "Recording")
	var rec_row := HBoxContainer.new()
	rec_row.add_theme_constant_override("separation", 8)
	col.add_child(rec_row)
	rec_button = _button(rec_row, "Start recording", _on_record_button, "Record everything Windows is playing, TinserBox included (Ctrl+R). MP3, or WAV if MP3 encoding is unavailable.")
	rec_status.size_flags_horizontal = SIZE_EXPAND_FILL
	rec_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rec_row.add_child(rec_status)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	col.add_child(name_row)
	rec_name.placeholder_text = "File name (default: date and time)"
	rec_name.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_child(rec_name)
	_button(name_row, "Rename last", func():
		if music.rename_last_recording(rec_name.text):
			director.show_toast("Renamed to " + music.last_recording.get_file())
			rec_name.text = ""
		else:
			director.show_toast("Type a new, unused name for the last recording"), "Rename the last finished recording to the name typed on the left")
	var dir_row := HBoxContainer.new()
	dir_row.add_theme_constant_override("separation", 8)
	col.add_child(dir_row)
	rec_dir_label.size_flags_horizontal = SIZE_EXPAND_FILL
	rec_dir_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rec_dir_label.text = music.recordings_dir()
	dir_row.add_child(rec_dir_label)
	_button(dir_row, "Choose folder", func():
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.set_meta("purpose", "recordings")
		file_dialog.popup_centered_ratio(0.7), "Where recordings are saved")

	_section(col, "Keys")
	var help := Label.new()
	help.text = "\n".join([
		"Space play/pause · Enter restart in 2 s · Left/Right seek",
		"Up/Down volume · M mute · N/P next/previous · S shuffle",
		"R repeat · F fullscreen · Esc show/hide · H hide until H",
		"1-9 presets · [ ] previous/next preset · Ctrl+M mini player",
		"Ctrl+R record system audio · Ctrl+Q quit",
		"%s screenshot · F3 diagnostics" % music.app_setting("screenshot_key", "F12"),
	])
	col.add_child(help)


func _build_transport(box: VBoxContainer) -> void:
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
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	shuffle_button = _icon_button(buttons, "shuffle", music.toggle_shuffle, "Shuffle (S)")
	_icon_button(buttons, "prev", music.previous_track, "Previous track (P)")
	_icon_button(buttons, "rewind", music.seek_by.bind(-music.SEEK_STEP), "Rewind 5 seconds (Left)")
	play_button = _icon_button(buttons, "play", music.toggle_pause, "Play / Pause (Space)")
	_icon_button(buttons, "forward", music.seek_by.bind(music.SEEK_STEP), "Forward 5 seconds (Right)")
	_icon_button(buttons, "next", music.next_track, "Next track (N)")
	repeat_button = _icon_button(buttons, "repeat", music.cycle_repeat, "Repeat: Off / All / One (R)")
	_icon_button(buttons, "restart", music.restart, "Restart song after 2 seconds (Enter)")
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	mute_button = _icon_button(buttons, "speaker", music.toggle_mute, "Mute / Unmute (M)")
	volume_slider = _slider(music.volume * 100.0, 100.0, _on_volume)
	volume_slider.custom_minimum_size.x = 110
	volume_slider.tooltip_text = "Volume (Up / Down, 5% steps)"
	buttons.add_child(volume_slider)
	volume_label.custom_minimum_size.x = 52
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	buttons.add_child(volume_label)
	_icon_button(buttons, "fullscreen", music.toggle_fullscreen, "Fullscreen (F)")
	lock_button = _icon_button(buttons, "lock", _on_lock, "Keep the interface visible (Esc shows / hides it)")
	lock_button.toggle_mode = true
	_icon_button(buttons, "hide", toggle_hide_mode, "Hide interface (H) - only H shows it again")
	_icon_button(buttons, "quit", music.quit_app, "Quit TinserBox (Ctrl+Q)")
	# Playback buttons (0-7) and volume (9-11) only apply to TinserBox's own player.
	for i in buttons.get_child_count():
		if i < 8 or (i >= 9 and i <= 11):
			player_only.append(buttons.get_child(i))
	player_only.append(seek_row)


# --- Overlay visibility ---------------------------------------------------------------

func toggle_hide_mode() -> void:
	hide_mode = not hide_mode
	music.set_app_setting("hide_mode", hide_mode)
	if mini:
		mini_panel.modulate.a = 0.0 if hide_mode else 1.0
		mini_panel.visible = not hide_mode
	idle = 0.0
	hidden_by_user = false
	overlay.modulate.a = 0.0 if hide_mode else 1.0
	overlay.visible = not hide_mode


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and event.ctrl_pressed:
		toggle_mini()
		get_viewport().set_input_as_handled()
		return
	if mini and _mini_input(event):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		# Typing in a text field: only Esc (leave the field) or a click elsewhere.
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			focus.release_focus()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and not focus.get_global_rect().has_point(event.position):
			focus.release_focus()
		if event is InputEventKey:
			idle = 0.0
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H and not event.ctrl_pressed:
		toggle_hide_mode()
		get_viewport().set_input_as_handled()
		return
	# In hide mode no activity reveals the interface; playback keys still reach the player.
	if hide_mode:
		return
	# Esc hides the interface immediately (even when locked); any other activity shows it again.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and overlay.visible:
		hidden_by_user = true
		overlay.modulate.a = 0.0
		overlay.visible = false
		get_viewport().set_input_as_handled()
		return
	# Only real activity counts: synthetic zero-distance motion (tooltips, window events) does not.
	var moved: bool = event is InputEventMouseMotion and event.relative.length() > 0.5
	if not mini and (moved or event is InputEventMouseButton or (event is InputEventKey and event.pressed)):
		hidden_by_user = false
		idle = 0.0
		overlay.modulate.a = 1.0
		overlay.visible = true


func _process(delta: float) -> void:
	idle += delta
	for p in popups:
		if is_instance_valid(p) and p.visible:
			idle = 0.0
	if file_dialog.visible or context_menu.visible:
		idle = 0.0
	var target := 1.0 if not hide_mode and not hidden_by_user and (lock_button.button_pressed or idle < IDLE_TIME) else 0.0
	if mini:
		# The mini bar uses the same fade; the full overlay stays hidden.
		mini_panel.modulate.a = move_toward(mini_panel.modulate.a, target, delta / FADE_TIME)
		mini_panel.visible = mini_panel.modulate.a > 0.0
		overlay.visible = false
		scroll_title.visible = false
		for b in mini_buttons:
			b.queue_redraw()
		syncing = true
		mini_volume.value = 0.0 if music.muted else music.volume * 100.0
		syncing = false
		return
	overlay.modulate.a = move_toward(overlay.modulate.a, target, delta / FADE_TIME)
	overlay.visible = overlay.modulate.a > 0.0
	_update_frame()

	scroll_title.visible = scroll_toggle.button_pressed and not overlay.visible and not hide_mode
	if scroll_title.visible:
		scroll_title.position.x -= SCROLL_SPEED * delta
		if scroll_title.position.x < -scroll_title.size.x:
			scroll_title.position.x = size.x

	if not overlay.visible:
		return
	var length: float = music.stream.get_length() if music.stream else 0.0
	seek_bar.max_value = maxf(length, 0.1)
	if not seeking:
		seek_bar.value = music.get_playback_position() if music.playing or music.stream_paused else 0.0
	time_label.text = "%s / %s" % [_time(seek_bar.value), _time(length)]
	for b in [play_button, shuffle_button, repeat_button, mute_button, lock_button]:
		b.queue_redraw()
	volume_label.text = "Muted" if music.muted else "%d%%" % roundi(music.volume * 100.0)
	syncing = true
	volume_slider.value = 0.0 if music.muted else music.volume * 100.0
	syncing = false
	_update_recording_ui()


## Hides the native title bar/borders while the overlay is hidden (optional). The client
## area's position and size are restored after each switch so content never moves.
func _update_frame() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var want_hidden := frame_toggle.button_pressed and not overlay.visible and not fullscreen
	if want_hidden == frame_hidden:
		return
	frame_hidden = want_hidden
	var window := get_window()
	var pos := window.position
	var window_size := window.size
	window.borderless = want_hidden
	window.size = window_size
	window.position = pos


# --- Playlist -----------------------------------------------------------------------

func _refresh_playlist() -> void:
	var filter := search.text.strip_edges().to_lower()
	var in_mood: bool = music.active_mood != music.ALL_MUSIC
	playlist.clear()
	visible_rows.clear()
	for i in music.tracks.size():
		var path: String = music.tracks[i]
		var label_text: String = music.display_name(path)
		if filter != "" and not (filter in label_text.to_lower()):
			continue
		var q: int = music.queue.find(path)
		var missing := in_mood and not FileAccess.file_exists(path)
		var row := playlist.add_item(("[%d] " % (q + 1) if q >= 0 else "") + label_text + ("  (missing)" if missing else ""))
		if missing:
			playlist.set_item_custom_fg_color(row, Color(GOLD, 0.35))
		visible_rows.append(i)
	sort_select.disabled = in_mood
	sort_select.tooltip_text = "Sort All Music" if not in_mood else "Moods keep their own order: drag songs to reorder"
	_refresh_moods()
	_highlight_current()
	_rebuild_mood_look()


func _refresh_moods() -> void:
	syncing = true
	mood_list.clear()
	for n in music.mood_names():
		var playing_here: bool = n == music.playing_mood and music.current_path != ""
		var count: int = music.library.size() if n == music.ALL_MUSIC else music.mood(n).tracks.size()
		var row := mood_list.add_item("%s  (%d)%s" % [n, count, "  - now" if playing_here else ""], _mood_icon(n))
		mood_list.set_item_metadata(row, n)
		if playing_here:
			mood_list.set_item_custom_fg_color(row, GOLD.lightened(0.25))
	mood_list.select(maxi(music.mood_names().find(music.active_mood), 0))
	syncing = false


## A small thumbnail: the mood's first background, else a swatch of its colours.
func _mood_icon(mood_name: String) -> Texture2D:
	var m: Dictionary = music.mood(mood_name)
	var key := mood_name + str(m.get("backgrounds", [])) + str(m.get("colors", []))
	if _thumbs.has(key):
		return _thumbs[key]
	var img: Image = null
	for b in m.get("backgrounds", []):
		var path: String = music.backgrounds_dir.path_join(b)
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
			break
	if img:
		img.resize(34, 20, Image.INTERPOLATE_BILINEAR)
	else:
		var cols: Array = m.get("colors", [])
		var a := Color(cols[0]) if cols.size() >= 2 else (GOLD if mood_name == music.ALL_MUSIC else Color(0.55, 0.42, 0.25))
		var b := Color(cols[1]) if cols.size() >= 2 else Color(0.12, 0.16, 0.14)
		img = Image.create(34, 20, false, Image.FORMAT_RGBA8)
		for x in 34:
			for y in 20:
				img.set_pixel(x, y, a.lerp(b, float(x) / 33.0))
	_thumbs[key] = ImageTexture.create_from_image(img)
	return _thumbs[key]


func _highlight_current() -> void:
	var row := visible_rows.find(music.current)
	playlist.deselect_all()
	if row >= 0 and music.current_path in music.tracks:
		playlist.select(row, false)
		playlist.ensure_current_is_visible()


func _selected_paths() -> Array:
	var out := []
	for r in playlist.get_selected_items():
		if r < visible_rows.size():
			out.append(music.tracks[visible_rows[r]])
	return out


func _on_playlist_clicked(row: int, at: Vector2, button: int) -> void:
	if row >= visible_rows.size() or button != MOUSE_BUTTON_RIGHT:
		return
	if not playlist.is_selected(row):
		playlist.deselect_all()
		playlist.select(row)
	context_row = visible_rows[row]
	var paths := _selected_paths()
	moods_menu.clear()
	var i := 0
	for n in music.moods:
		moods_menu.add_check_item(n, i)
		moods_menu.set_item_checked(i, paths.all(func(p): return p in music.mood(n).tracks))
		i += 1
	context_menu.set_item_disabled(context_menu.get_item_index(3), music.moods.is_empty())
	context_menu.set_item_text(context_menu.get_item_index(2), "Remove from this mood" if music.active_mood != music.ALL_MUSIC else "Remove from All Music")
	context_menu.position = Vector2i(playlist.get_screen_position() + at)
	context_menu.popup()


## Checkable mood tags: tick to add the selected songs to a mood, untick to remove them.
func _on_mood_tag(id: int) -> void:
	var mood_name: String = moods_menu.get_item_text(moods_menu.get_item_index(id))
	var paths := _selected_paths()
	var idx := moods_menu.get_item_index(id)
	if moods_menu.is_item_checked(idx):
		music.remove_from_mood(mood_name, paths)
	else:
		music.add_to_mood(mood_name, paths)
	moods_menu.set_item_checked(idx, not moods_menu.is_item_checked(idx))


func _on_new_mood() -> void:
	var n := mood_name_edit.text.strip_edges()
	if music.create_mood(n):
		mood_name_edit.text = ""
		director.show_toast("Created mood %s: drop songs onto it" % n)
	else:
		director.show_toast("Type a new, unused mood name first")


func _on_rename_mood() -> void:
	if music.rename_mood(music.active_mood, mood_name_edit.text):
		mood_name_edit.text = ""
		_rebuild_mood_look(true)
	else:
		director.show_toast("Select one of your moods and type a new, unused name")


func _on_delete_mood() -> void:
	if music.active_mood == music.ALL_MUSIC:
		director.show_toast("All Music is the permanent library and cannot be deleted")
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete the mood \"%s\"?\nIts songs stay in All Music and on disk." % music.active_mood
	add_child(dlg)
	var n: String = music.active_mood
	dlg.confirmed.connect(func():
		music.delete_mood(n)
		director.show_toast("Deleted mood %s (songs are kept)" % n))
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	dlg.popup_centered()


func _add_preset_to_mood() -> void:
	var mood_name: String = music.active_mood
	if mood_name == music.ALL_MUSIC:
		director.show_toast("Select a mood in the Moods tab first")
		return
	var list: Array = Array(music.mood(mood_name).presets).duplicate()
	if not (director.working_name in list):
		list.append(director.working_name)
		music.set_mood_value(mood_name, "presets", list)
	director.show_toast("%s added to %s" % [director.working_name, mood_name])
	_rebuild_mood_look(true)


## Songs are dragged with their paths: onto a mood (adds them) or within a mood (reorders).
func _playlist_drag(at: Vector2) -> Variant:
	var row := playlist.get_item_at_position(at, true)
	if row < 0:
		return null
	if not playlist.is_selected(row):
		playlist.select(row)
	var paths := _selected_paths()
	var preview := Label.new()
	preview.text = playlist.get_item_text(row) if paths.size() == 1 else "%d songs" % paths.size()
	preview.add_theme_color_override("font_color", GOLD)
	playlist.set_drag_preview(preview)
	return {"tinserbox_tracks": paths, "tinserbox_row": visible_rows[row]}


func _playlist_can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("tinserbox_tracks") and data.tinserbox_tracks.size() == 1 \
		and music.active_mood != music.ALL_MUSIC and search.text.strip_edges() == ""


func _playlist_drop(at: Vector2, data: Variant) -> void:
	var row := playlist.get_item_at_position(at, true)
	var target: int = visible_rows[row] if row >= 0 else music.tracks.size() - 1
	music.move_in_mood(data.tinserbox_row, target)


func _mood_drag(at: Vector2) -> Variant:
	var row := mood_list.get_item_at_position(at, true)
	if row <= 0:
		return null  # All Music stays first.
	var preview := Label.new()
	preview.text = str(mood_list.get_item_metadata(row))
	preview.add_theme_color_override("font_color", GOLD)
	mood_list.set_drag_preview(preview)
	return {"tinserbox_mood": str(mood_list.get_item_metadata(row))}


func _mood_can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var row := mood_list.get_item_at_position(at, true)
	if data.has("tinserbox_tracks"):
		return row > 0
	return data.has("tinserbox_mood")


func _mood_drop(at: Vector2, data: Variant) -> void:
	var row := mood_list.get_item_at_position(at, true)
	if data.has("tinserbox_tracks"):
		music.add_to_mood(str(mood_list.get_item_metadata(row)), data.tinserbox_tracks)
	else:
		music.move_mood(data.tinserbox_mood, maxi(row - 1, 0) if row >= 0 else music.moods.size())


func _on_context(id: int) -> void:
	match id:
		0: music.play_track(context_row)
		1:
			for p in _selected_paths():
				music.queue_next(music.tracks.find(p))
		2:
			var rows := []
			for p in _selected_paths():
				rows.append(music.tracks.find(p))
			music.remove_tracks(rows)
		4: music.clear_queue()


func _open_dialog(mode: FileDialog.FileMode) -> void:
	file_dialog.file_mode = mode
	file_dialog.set_meta("purpose", "music")
	file_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio"]) if mode == FileDialog.FILE_MODE_OPEN_FILES else PackedStringArray()
	file_dialog.popup_centered_ratio(0.7)


func _on_dir_selected(dir: String) -> void:
	if file_dialog.get_meta("purpose", "music") == "recordings":
		music.set_app_setting("recordings_dir", dir)
		rec_dir_label.text = dir
	elif file_dialog.get_meta("purpose", "music") == "screenshots":
		music.set_app_setting("screenshot_dir", dir)
		shot_dir_label.text = dir
	else:
		music.add_folder(dir)


# --- Song / Studio sync --------------------------------------------------------------

func _on_track_changed(_index: int) -> void:
	if music.tracks.is_empty() or music.current_path == "":
		title.text = "NO TRACKS IN MUSIC/"
		return
	title.text = music.display_name(music.current_path).to_upper()
	mini_title.text = title.text
	scroll_title.text = title.text
	scroll_title.reset_size()
	scroll_title.position.x = size.x
	_refresh_playlist()


## Shows only the settings that apply to the main layer's current visualizer.
func _rebuild_mode_grid() -> void:
	var mode: String = director.working.main.mode
	if mode == mode_grid_for:
		return
	mode_grid_for = mode
	for c in mode_grid.get_children():
		c.queue_free()
	for k in studio_controls.keys():
		if studio_controls[k].get_parent() == mode_grid:
			studio_controls.erase(k)
	var params: Dictionary = Layer.MODE_PARAMS.get(mode, {})
	for key in params:
		var spec: Array = params[key]
		_studio_slider(mode_grid, spec[0], "main", key, spec[1], spec[2], spec[3])


func _studio_color(button: ColorPickerButton, index: int) -> ColorPickerButton:
	button.edit_alpha = false
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 24
	button.color_changed.connect(func(c: Color):
		if syncing:
			return
		if index < 0:
			var cols: Array = director.working.colors.duplicate()
			cols[-index - 1] = "#" + c.to_html(false)
			director.edit("", "colors", cols)
		else:
			var pal: Array = director.working.get("palette", []).duplicate()
			pal[index] = "#" + c.to_html(false)
			director.edit("", "palette", pal))
	popups.append(button.get_popup())
	return button


func _reset_colours() -> void:
	var source := {}
	for b in Presets.builtins():
		if b.name == director.working_name:
			source = b
	var colors: Array = source.get("colors", Presets.DEFAULT.colors)
	var pal: Array = source.get("palette", Presets.PALETTE)
	director.edit("", "colors", colors.duplicate())
	director.edit("", "palette", pal.duplicate())


func _sync_studio() -> void:
	if director.working.is_empty():
		return
	_rebuild_mode_grid()
	syncing = true
	main_color_button.color = Color(director.working.colors[0])
	second_color_button.color = Color(director.working.colors[1])
	var pal: Array = director.working.get("palette", [])
	for k in mini(pal.size(), palette_buttons.size()):
		palette_buttons[k].color = Color(pal[k])
	_fill_preset_list(preset_select, director.working_name)
	for path in studio_controls:
		var parts: PackedStringArray = path.split("/")
		var value = director.working[parts[1]] if parts[0] == "" else director.working[parts[0]][parts[1]]
		var control: Control = studio_controls[path]
		if control is OptionButton:
			var keys: Array = control.get_meta("keys")
			control.select(maxi(keys.find(value), 0))
		elif control is CheckButton:
			control.button_pressed = bool(value)
		elif control is HSlider:
			control.value = float(value)
	syncing = false


func _fill_preset_list(select: OptionButton, selected: String) -> void:
	select.clear()
	var names: Array = director.presets.names()
	for i in names.size():
		select.add_item(names[i] if i >= 9 else "%d  %s" % [i + 1, names[i]])
		select.set_item_metadata(i, names[i])
	for i in names.size():
		if names[i] == selected:
			select.select(i)


# --- Mini player --------------------------------------------------------------------

func _build_mini() -> void:
	mini_panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	mini_panel.grow_vertical = GROW_DIRECTION_BEGIN
	mini_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.04, 0.72)
	sb.border_color = Color(GOLD, 0.2)
	sb.border_width_top = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	mini_panel.add_theme_stylebox_override("panel", sb)
	add_child(mini_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	mini_panel.add_child(col)
	mini_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mini_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mini_title.add_theme_font_override("font", BOLD_FONT)
	mini_title.add_theme_font_size_override("font_size", 13)
	mini_title.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(mini_title)
	mini_controls.add_theme_constant_override("separation", 4)
	mini_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(mini_controls)
	mini_buttons.append(_icon_button(mini_controls, "prev", music.previous_track, "Previous track (P)"))
	mini_buttons.append(_icon_button(mini_controls, "play", music.toggle_pause, "Play / Pause (Space)"))
	mini_buttons.append(_icon_button(mini_controls, "next", music.next_track, "Next track (N)"))
	var gap := Control.new()
	gap.custom_minimum_size.x = 14
	mini_controls.add_child(gap)
	mini_buttons.append(_icon_button(mini_controls, "speaker", music.toggle_mute, "Mute / Unmute (M)"))
	mini_volume = _slider(music.volume * 100.0, 100.0, _on_volume)
	mini_volume.custom_minimum_size.x = 100
	mini_volume.tooltip_text = "Volume (Up / Down)"
	mini_controls.add_child(mini_volume)
	mini_buttons.append(_icon_button(mini_controls, "mini_exit", toggle_mini, "Back to the full player (Ctrl+M)"))


## Ctrl+M: playback, visuals and EQ continue untouched; only the window changes.
func toggle_mini() -> void:
	var window := get_window()
	if not mini:
		_saved_window = {
			"mode": window.mode, "position": window.position, "size": window.size,
			"borderless": window.borderless, "on_top": window.always_on_top, "min_size": window.min_size,
		}
		mini = true
		frame_hidden = false
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		window.min_size = MINI_SIZE
		window.borderless = true
		window.always_on_top = true
		window.size = MINI_SIZE
		overlay.visible = false
		mini_panel.visible = true
		mini_panel.modulate.a = 1.0
		idle = 0.0
	else:
		mini = false
		mini_panel.visible = false
		window.always_on_top = _saved_window.get("on_top", false)
		window.borderless = _saved_window.get("borderless", false)
		window.min_size = _saved_window.get("min_size", Vector2i(800, 600))
		window.size = _saved_window.get("size", Vector2i(1672, 941))
		window.position = _saved_window.get("position", window.position)
		window.mode = _saved_window.get("mode", Window.MODE_WINDOWED)
		overlay.visible = true
		overlay.modulate.a = 1.0
		idle = 0.0


## Mini mode input: drag the window by any area outside the controls; F leaves mini mode
## and goes fullscreen. Returns true when the event was used.
func _mini_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F and not event.ctrl_pressed:
		toggle_mini()
		music.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not (mini_panel.visible and mini_controls.get_global_rect().has_point(event.position)):
			_drag_from = DisplayServer.mouse_get_position()
			_drag_window = get_window().position
		elif not event.pressed:
			_drag_from = Vector2i(-1, -1)
	elif event is InputEventMouseMotion and _drag_from.x >= 0:
		get_window().position = _drag_window + DisplayServer.mouse_get_position() - _drag_from
	if event is InputEventMouseMotion and event.relative.length() > 0.5 or event is InputEventMouseButton or (event is InputEventKey and event.pressed):
		if not hide_mode:
			hidden_by_user = false
			idle = 0.0
			mini_panel.modulate.a = 1.0
			mini_panel.visible = true
	return false


func _update_source_ui() -> void:
	var player: bool = music.source == "player"
	for c in player_only:
		c.visible = player
	source_select.select(0 if player else 1)


func _on_record_button() -> void:
	if music.recording:
		music.stop_recording()
	else:
		music.start_recording(rec_name.text)
		rec_name.text = ""


func _update_recording_ui() -> void:
	rec_button.text = "Stop recording" if music.recording else "Start recording"
	if music.recording:
		var secs := int(music.recording_seconds())
		rec_status.text = "Recording %d:%02d%s" % [secs / 60, secs % 60, "" if music.rec_format == "" else " (" + music.rec_format.to_upper() + ")"]
	elif music.last_recording != "":
		rec_status.text = "Last: " + music.last_recording.get_file()
	else:
		rec_status.text = "Windows only. Recording starts only when you press the button."


func _on_save_as() -> void:
	var n := preset_name_edit.text.strip_edges()
	if n != "":
		director.save_working(director.presets.unique_name(n))
		preset_name_edit.text = ""


func _on_rename() -> void:
	if director.rename_working(preset_name_edit.text.strip_edges()):
		preset_name_edit.text = ""
	else:
		director.show_toast("Only your own presets can be renamed, to an unused name")


func _choose_screenshot_dir() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.set_meta("purpose", "screenshots")
	file_dialog.popup_centered_ratio(0.7)


func _toggle_diag() -> void:
	director.diag.visible = not director.diag.visible
	director._update_diag()


func _studio_slider(g: GridContainer, text: String, section: String, key: String, lo: float, hi: float, step := 0.01) -> void:
	_label(g, text)
	var s := _slider(0.0, hi, func(v: float):
		if not syncing:
			director.edit(section, key, v))
	s.min_value = lo
	s.step = step
	studio_controls[section + "/" + key] = s
	_fill(g, s)


func _studio_option(g: GridContainer, text: String, section: String, key: String, items: Dictionary) -> void:
	_label(g, text)
	var o := OptionButton.new()
	for k in items:
		o.add_item(items[k])
	o.set_meta("keys", items.keys())
	o.item_selected.connect(func(i: int):
		if not syncing:
			director.edit(section, key, items.keys()[i]))
	studio_controls[section + "/" + key] = o
	popups.append(o.get_popup())
	_fill(g, o)


func _studio_check(g: GridContainer, text: String, section: String, key: String, tooltip: String) -> void:
	_label(g, text)
	var c := CheckButton.new()
	c.tooltip_text = tooltip
	c.toggled.connect(func(on: bool):
		if not syncing:
			director.edit(section, key, on))
	studio_controls[section + "/" + key] = c
	_fill(g, c)


func _setting_check(g: GridContainer, text: String, key: String, initial: bool, tooltip: String, extra := Callable()) -> void:
	_label(g, text)
	var c := CheckButton.new()
	c.button_pressed = music.app_setting(key, initial)
	c.tooltip_text = tooltip
	c.toggled.connect(func(on: bool):
		music.set_app_setting(key, on)
		if extra.is_valid():
			extra.call(on))
	_fill(g, c)


# --- Small builders -----------------------------------------------------------------

func _scroll_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	return col


func _section(col: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BOLD_FONT)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(GOLD, 0.95))
	col.add_child(l)


func _grid4(col: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 8)
	col.add_child(g)
	return g


func _label(g: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 120
	l.add_theme_color_override("font_color", Color(GOLD, 0.8))
	g.add_child(l)


func _fill(g: Control, control: Control) -> void:
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	control.focus_mode = FOCUS_NONE if not (control is LineEdit) else control.focus_mode
	if control is OptionButton and not (control.get_popup() in popups):
		popups.append(control.get_popup())
	g.add_child(control)


func _icon_button(parent: Control, kind: String, action: Callable, tooltip: String) -> Button:
	var b := _button(parent, "", action, tooltip)
	b.custom_minimum_size = Vector2(36, 30)
	b.draw.connect(_draw_icon.bind(b, kind))
	return b


func _button(parent: Control, text: String, action: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
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


func _time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


# --- Transport callbacks ------------------------------------------------------------

func _on_volume(v: float) -> void:
	if not syncing:
		music.set_volume(v / 100.0)


func _on_eq_changed(v: float, value_label: Label) -> void:
	value_label.text = "%+.1f" % v
	var gains := []
	for s in eq_sliders:
		gains.append(s.value)
	music.set_app_setting("eq_gains", gains)
	music.apply_eq()


func _on_seek_started() -> void:
	seeking = true


func _on_seek_ended(_changed: bool) -> void:
	seeking = false
	music.seek_to(seek_bar.value)


func _on_lock() -> void:
	lock_button.queue_redraw()


# --- Icons --------------------------------------------------------------------------

func _poly(b: Button, c: Vector2, points: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(c + p)
	b.draw_colored_polygon(pts, col)


func _line(b: Button, c: Vector2, points: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(c + p)
	b.draw_polyline(pts, col, 2.0, true)


func _arrow(b: Button, tip: Vector2, dir: Vector2, col: Color) -> void:
	var n := dir.orthogonal()
	b.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 5.0 + n * 3.5, tip - dir * 5.0 - n * 3.5]), col)


## Simple vector icons in the gold palette; inactive toggles are drawn dimmed.
func _draw_icon(b: Button, kind: String) -> void:
	var c := (b.size * 0.5).round()
	var col := GOLD.lightened(0.15) if b.is_hovered() else GOLD
	var dim := Color(GOLD, 0.35)
	match kind:
		"play":
			if music.playing and not music.stream_paused:
				b.draw_rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), col)
				b.draw_rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), col)
			else:
				_poly(b, c, [Vector2(-5, -8), Vector2(8, 0), Vector2(-5, 8)], col)
		"prev":
			b.draw_rect(Rect2(c + Vector2(-8, -7), Vector2(2.5, 14)), col)
			_poly(b, c, [Vector2(7, -7), Vector2(7, 7), Vector2(-5, 0)], col)
		"next":
			b.draw_rect(Rect2(c + Vector2(5.5, -7), Vector2(2.5, 14)), col)
			_poly(b, c, [Vector2(-7, -7), Vector2(-7, 7), Vector2(5, 0)], col)
		"rewind":
			_poly(b, c, [Vector2(0, -6), Vector2(0, 6), Vector2(-8, 0)], col)
			_poly(b, c, [Vector2(8, -6), Vector2(8, 6), Vector2(0, 0)], col)
		"forward":
			_poly(b, c, [Vector2(0, -6), Vector2(0, 6), Vector2(8, 0)], col)
			_poly(b, c, [Vector2(-8, -6), Vector2(-8, 6), Vector2(0, 0)], col)
		"restart":
			var end := deg_to_rad(230.0)
			b.draw_arc(c, 7.0, deg_to_rad(-40.0), end, 20, col, 2.0, true)
			_arrow(b, c + Vector2.from_angle(end) * 7.0 + Vector2(1, -2), Vector2(-sin(end), cos(end)), col)
		"shuffle":
			var sc := col if music.shuffle else dim
			_line(b, c, [Vector2(-9, -5), Vector2(-3, -5), Vector2(3, 5), Vector2(6, 5)], sc)
			_line(b, c, [Vector2(-9, 5), Vector2(-3, 5), Vector2(3, -5), Vector2(6, -5)], sc)
			_arrow(b, c + Vector2(10, 5), Vector2.RIGHT, sc)
			_arrow(b, c + Vector2(10, -5), Vector2.RIGHT, sc)
		"repeat":
			var rc := dim if music.repeat == music.Repeat.OFF else col
			_line(b, c, [Vector2(-8, 3), Vector2(-8, -5), Vector2(5, -5)], rc)
			_arrow(b, c + Vector2(9, -5), Vector2.RIGHT, rc)
			_line(b, c, [Vector2(8, -3), Vector2(8, 5), Vector2(-5, 5)], rc)
			_arrow(b, c + Vector2(-9, 5), Vector2.LEFT, rc)
			if music.repeat == music.Repeat.ONE:
				b.draw_string(b.get_theme_font("font"), c + Vector2(-3, 4), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, rc)
		"speaker":
			var s := c + Vector2(-4, 0)
			_poly(b, s, [Vector2(-6, -3), Vector2(-2, -3), Vector2(3, -8), Vector2(3, 8), Vector2(-2, 3), Vector2(-6, 3)], col)
			if music.muted:
				b.draw_line(s + Vector2(6, -4), s + Vector2(13, 4), col, 2.0, true)
				b.draw_line(s + Vector2(13, -4), s + Vector2(6, 4), col, 2.0, true)
			else:
				b.draw_arc(s + Vector2(3, 0), 5.0, -0.9, 0.9, 8, col, 1.6, true)
				if music.volume > 0.5:
					b.draw_arc(s + Vector2(3, 0), 9.0, -0.9, 0.9, 10, col, 1.6, true)
		"fullscreen":
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					_line(b, c, [Vector2(sx * 8, sy * 3), Vector2(sx * 8, sy * 8), Vector2(sx * 3, sy * 8)], col)
		"lock":
			var locked := lock_button.button_pressed
			var lc := col if locked else dim
			b.draw_rect(Rect2(c + Vector2(-6, -1), Vector2(12, 9)), lc)
			b.draw_arc(c + Vector2(0 if locked else 4, -1), 4.5, PI, TAU if locked else PI * 1.75, 12, lc, 2.0, true)
		"hide":
			b.draw_arc(c + Vector2(-2, 5), 8.0, deg_to_rad(-150.0), deg_to_rad(-30.0), 12, col, 1.8, true)
			b.draw_arc(c + Vector2(-2, -5), 8.0, deg_to_rad(30.0), deg_to_rad(150.0), 12, col, 1.8, true)
			b.draw_circle(c + Vector2(-2, 0), 2.2, col)
			b.draw_line(c + Vector2(-9, 6), c + Vector2(5, -6), col, 1.8, true)
			b.draw_string(BOLD_FONT, c + Vector2(8, 10), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		"mini_exit":
			# Two corners pointing outward: back to the full player.
			_line(b, c, [Vector2(-8, -2), Vector2(-8, -8), Vector2(-2, -8)], col)
			_line(b, c, [Vector2(8, 2), Vector2(8, 8), Vector2(2, 8)], col)
			b.draw_line(c + Vector2(-8, -8), c + Vector2(-3, -3), col, 2.0, true)
			b.draw_line(c + Vector2(8, 8), c + Vector2(3, 3), col, 2.0, true)
		"quit":
			var qc := Color(1.0, 0.62, 0.45)
			b.draw_arc(c + Vector2(0, 1), 7.0, deg_to_rad(-55.0), deg_to_rad(235.0), 20, qc, 2.0, true)
			b.draw_line(c + Vector2(0, -8), c + Vector2(0, 0), qc, 2.0, true)


# --- Theme --------------------------------------------------------------------------

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 13
	th.default_font = LIGHT_FONT
	for type in ["Button", "TabContainer"]:
		th.set_font("font", type, BOLD_FONT)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.05, 0.04, 0.66)
	bg.border_color = Color(GOLD, 0.22)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(16)
	th.set_stylebox("panel", "PanelContainer", bg)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(GOLD, {"normal": 0.06, "hover": 0.15, "pressed": 0.26, "hover_pressed": 0.3, "disabled": 0.03}[state])
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if state in ["pressed", "hover_pressed"]:
			sb.border_color = Color(GOLD, 0.5)
			sb.border_width_bottom = 1
		th.set_stylebox(state, "Button", sb)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", GOLD)
	th.set_color("font_hover_color", "Button", GOLD.lightened(0.2))

	th.set_color("font_color", "Label", GOLD)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		th.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
		th.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())

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
		th.set_icon("grabber_highlight", slider, _dot(7, GOLD.lightened(0.2)))

	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0.18)
	inner.set_corner_radius_all(6)
	inner.set_content_margin_all(6)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(GOLD, 0.18)
	selected.border_color = Color(GOLD, 0.45)
	selected.border_width_left = 2
	selected.set_corner_radius_all(4)
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(GOLD, 0.08)
	hovered.set_corner_radius_all(4)
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

	var tab_sel := selected.duplicate()
	tab_sel.border_width_left = 0
	tab_sel.border_width_bottom = 2
	th.set_stylebox("panel", "TabContainer", inner)
	th.set_stylebox("tab_selected", "TabContainer", tab_sel)
	th.set_stylebox("tab_hovered", "TabContainer", hovered.duplicate())
	var unselected := StyleBoxEmpty.new()
	th.set_stylebox("tab_unselected", "TabContainer", unselected)
	th.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	for s in [tab_sel, th.get_stylebox("tab_hovered", "TabContainer"), unselected]:
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 4
		s.content_margin_bottom = 4
	th.set_color("font_selected_color", "TabContainer", GOLD)
	th.set_color("font_hovered_color", "TabContainer", GOLD)
	th.set_color("font_unselected_color", "TabContainer", Color(GOLD, 0.6))

	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0.3)
	field.border_color = Color(GOLD, 0.25)
	field.set_border_width_all(1)
	field.set_corner_radius_all(6)
	field.content_margin_left = 8
	field.content_margin_right = 8
	field.content_margin_top = 4
	field.content_margin_bottom = 4
	var field_focus := field.duplicate()
	field_focus.border_color = Color(GOLD, 0.6)
	th.set_stylebox("normal", "LineEdit", field)
	th.set_stylebox("focus", "LineEdit", field_focus)
	th.set_color("font_color", "LineEdit", GOLD)
	th.set_color("font_placeholder_color", "LineEdit", Color(GOLD, 0.4))
	th.set_color("caret_color", "LineEdit", GOLD)

	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.04, 0.07, 0.05, 0.96)
	popup.border_color = Color(GOLD, 0.3)
	popup.set_border_width_all(1)
	popup.set_corner_radius_all(6)
	popup.set_content_margin_all(6)
	th.set_stylebox("panel", "PopupMenu", popup)
	th.set_stylebox("hover", "PopupMenu", hovered)
	th.set_color("font_color", "PopupMenu", Color(GOLD, 0.85))
	th.set_color("font_hover_color", "PopupMenu", GOLD)
	th.set_stylebox("panel", "TooltipPanel", popup)
	th.set_color("font_color", "TooltipLabel", GOLD)
	th.set_font("font", "TooltipLabel", LIGHT_FONT)
	th.set_font_size("font_size", "TooltipLabel", 12)

	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(GOLD, 0.06)
	bar.set_corner_radius_all(3)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(GOLD, 0.35)
	grab.set_corner_radius_all(3)
	th.set_stylebox("scroll", "VScrollBar", bar)
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab)
	return th


func _dot(radius: int, color: Color) -> ImageTexture:
	var img := Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	for x in radius * 2:
		for y in radius * 2:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			img.set_pixel(x, y, Color(color, clampf(radius - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
