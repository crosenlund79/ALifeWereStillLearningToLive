extends AudioStreamPlayer

signal track_changed(index: int)

const EXTENSIONS := ["mp3", "ogg", "wav"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg"]
const SEEK_STEP := 5.0
const RESTART_DELAY := 2.0
const APP := "_app"  # Config section for app-wide settings; song sections are keyed by filename.
const EQ_BANDS := [60.0, 150.0, 400.0, 1000.0, 2400.0, 6000.0, 15000.0]
const EQ21_HZ := [22, 32, 44, 63, 90, 125, 175, 250, 350, 500, 700, 1000, 1400, 2000, 2800, 4000, 5600, 8000, 11000, 16000, 22000]

# External folders sit next to the executable (or in the project folder when run from the editor).
var base_dir: String = ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
var music_dir := base_dir.path_join("music")
var backgrounds_dir := base_dir.path_join("backgrounds")
var config_path := base_dir.path_join("settings.cfg")
var settings := ConfigFile.new()

var tracks: Array[String] = []
var current := 0
var restart_timer := Timer.new()
var eq := AudioEffectEQ21.new()
var eq_index := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(music_dir)
	DirAccess.make_dir_recursive_absolute(backgrounds_dir)
	if FileAccess.file_exists(config_path):
		settings.load(config_path)
	else:
		settings.save(config_path)

	AudioServer.add_bus_effect(0, eq)
	eq_index = AudioServer.get_bus_effect_count(0) - 1
	apply_eq()

	restart_timer.one_shot = true
	restart_timer.timeout.connect(func(): play(0.0))
	add_child(restart_timer)
	finished.connect(next_track)

	var names := []
	for file in DirAccess.get_files_at(music_dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			tracks.append(music_dir.path_join(file))
			names.append(file)
	# Exported builds also play tracks bundled into the package (listed as "track.mp3.import").
	if not OS.has_feature("editor"):
		for file in DirAccess.get_files_at("res://music"):
			var track := file.trim_suffix(".import").trim_suffix(".remap")
			if track.get_extension().to_lower() in EXTENSIONS and track not in names:
				tracks.append("res://music/" + track)
				names.append(track)
	tracks.sort_custom(func(a, b): return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	play_track(0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.echo and event.keycode not in [KEY_LEFT, KEY_RIGHT]:
		return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_ENTER, KEY_KP_ENTER: restart()
		KEY_RIGHT: seek_by(SEEK_STEP)
		KEY_LEFT: seek_by(-SEEK_STEP)
		KEY_F: toggle_fullscreen()


func play_track(index: int) -> void:
	if tracks.is_empty():
		return
	restart_timer.stop()
	current = wrapi(index, 0, tracks.size())
	stream = _load_stream(tracks[current])
	play()
	stream_paused = false
	track_changed.emit(current)


func next_track() -> void:
	play_track(current + 1)


func previous_track() -> void:
	play_track(current - 1)


func toggle_pause() -> void:
	if restart_timer.is_stopped():
		stream_paused = not stream_paused


func restart() -> void:
	stop()
	stream_paused = false
	restart_timer.start(RESTART_DELAY)


func seek_by(offset: float) -> void:
	seek_to(get_playback_position() + offset)


func seek_to(pos: float) -> void:
	# Seeking waits while a restart is pending.
	if stream == null or not restart_timer.is_stopped():
		return
	var was_paused := stream_paused
	play(clampf(pos, 0.0, stream.get_length()))
	stream_paused = was_paused


func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func list_backgrounds() -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(backgrounds_dir):
		if file.get_extension().to_lower() in IMAGE_EXTENSIONS:
			files.append(file)
	files.sort()
	return files


## Per-song settings for the current track, keyed by filename.
func song_setting(key: String, fallback: Variant) -> Variant:
	return settings.get_value(tracks[current].get_file(), key, fallback) if not tracks.is_empty() else fallback


## Passing null removes the setting.
func set_song_setting(key: String, value: Variant) -> void:
	if not tracks.is_empty():
		settings.set_value(tracks[current].get_file(), key, value)
		settings.save(config_path)


func app_setting(key: String, fallback: Variant) -> Variant:
	return settings.get_value(APP, key, fallback)


func set_app_setting(key: String, value: Variant) -> void:
	settings.set_value(APP, key, value)
	settings.save(config_path)


## Spreads the 7 user bands across Godot's native 21-band EQ by log-frequency interpolation.
func apply_eq() -> void:
	var gains: Array = app_setting("eq_gains", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in EQ21_HZ.size():
		var x := log(float(EQ21_HZ[i]))
		var db: float = gains[0] if x <= log(EQ_BANDS[0]) else gains[6]
		for b in 6:
			var x0: float = log(EQ_BANDS[b])
			var x1: float = log(EQ_BANDS[b + 1])
			if x >= x0 and x <= x1:
				db = lerpf(gains[b], gains[b + 1], (x - x0) / (x1 - x0))
		eq.set_band_gain_db(i, db)
	AudioServer.set_bus_effect_enabled(0, eq_index, app_setting("eq_enabled", true))


func _load_stream(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path)
	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			return mp3
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
	return _load_wav(path)


## Minimal PCM WAV reader (8/16-bit); Godot 4.3 has no runtime WAV loader.
func _load_wav(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	var wav := AudioStreamWAV.new()
	var i := 12
	while i + 8 <= bytes.size():
		var id := bytes.slice(i, i + 4).get_string_from_ascii()
		var size := bytes.decode_u32(i + 4)
		if id == "fmt ":
			wav.stereo = bytes.decode_u16(i + 10) == 2
			wav.mix_rate = bytes.decode_u32(i + 12)
			wav.format = AudioStreamWAV.FORMAT_8_BITS if bytes.decode_u16(i + 22) == 8 else AudioStreamWAV.FORMAT_16_BITS
		elif id == "data":
			var pcm := bytes.slice(i + 8, i + 8 + size)
			if wav.format == AudioStreamWAV.FORMAT_8_BITS:
				for j in pcm.size():
					pcm[j] = (pcm[j] + 128) & 0xFF  # WAV 8-bit is unsigned; Godot expects signed.
			wav.data = pcm
		i += 8 + size + (size & 1)
	return wav
