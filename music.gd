extends AudioStreamPlayer

signal track_changed(index: int)

enum Repeat { OFF, ALL, ONE }

const EXTENSIONS := ["mp3", "ogg", "wav"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg"]
const SEEK_STEP := 5.0
const VOLUME_STEP := 0.05
const RESTART_DELAY := 2.0
const APP := "_app"  # Config section for app-wide settings; song sections are keyed by filename.
const EQ_BANDS := [60.0, 150.0, 400.0, 1000.0, 2400.0, 6000.0, 15000.0]
const EQ21_HZ := [22, 32, 44, 63, 90, 125, 175, 250, 350, 500, 700, 1000, 1400, 2000, 2800, 4000, 5600, 8000, 11000, 16000, 22000]
const MEDIA_HELPER := "TinserBoxMedia.exe"

var exe_dir := OS.get_executable_path().get_base_dir()
var base_dir := _data_dir()
var music_dir := base_dir.path_join("music")
var backgrounds_dir := base_dir.path_join("backgrounds")
var config_path := base_dir.path_join("settings.cfg")
var settings := ConfigFile.new()

var tracks: Array[String] = []
var current := 0
var order: Array[int] = []  # Play order (shuffled or sequential); pos indexes into it.
var pos := 0
var shuffle := false
var repeat := Repeat.ALL
var volume := 1.0
var muted := false
var restart_timer := Timer.new()
var eq := AudioEffectEQ21.new()
var eq_index := 0

# Windows media keys via the SMTC helper (see tools/media_keys).
var media_udp := PacketPeerUDP.new()
var media_pid := -1
var media_helper := false
var media_state := ""


## Editor: the project folder. Portable build: next to the executable. Installed build
## (the installer leaves installed.flag next to the exe): Documents\TinserBox, since
## Program Files is read-only.
func _data_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	if FileAccess.file_exists(exe_dir.path_join("installed.flag")):
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("TinserBox")
	return exe_dir


func _ready() -> void:
	var first_run := not DirAccess.dir_exists_absolute(music_dir)
	DirAccess.make_dir_recursive_absolute(music_dir)
	DirAccess.make_dir_recursive_absolute(backgrounds_dir)
	# Installed builds seed the user's library with the bundled songs on first launch.
	if first_run and base_dir != exe_dir:
		for folder in ["music", "backgrounds"]:
			for file in DirAccess.get_files_at(exe_dir.path_join(folder)):
				DirAccess.copy_absolute(exe_dir.path_join(folder).path_join(file), base_dir.path_join(folder).path_join(file))
	if FileAccess.file_exists(config_path):
		settings.load(config_path)
	else:
		settings.save(config_path)

	AudioServer.add_bus_effect(0, eq)
	eq_index = AudioServer.get_bus_effect_count(0) - 1
	apply_eq()
	shuffle = app_setting("shuffle", false)
	repeat = app_setting("repeat", Repeat.ALL)
	volume = app_setting("volume", 1.0)
	muted = app_setting("muted", false)
	_apply_volume()

	restart_timer.one_shot = true
	restart_timer.timeout.connect(func(): play(0.0))
	add_child(restart_timer)
	finished.connect(_on_finished)

	for file in DirAccess.get_files_at(music_dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			tracks.append(music_dir.path_join(file))
	tracks.sort_custom(func(a, b): return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	_build_order(-1)  # Shuffle on: start with a random track.
	if not tracks.is_empty():
		_play(order[0])
	_start_media_helper()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.echo and event.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_ENTER, KEY_KP_ENTER: restart()
		KEY_RIGHT: seek_by(SEEK_STEP)
		KEY_LEFT: seek_by(-SEEK_STEP)
		KEY_F: toggle_fullscreen()
		KEY_N: next_track()
		KEY_P: previous_track()
		KEY_S: toggle_shuffle()
		KEY_R: cycle_repeat()
		KEY_UP: change_volume(VOLUME_STEP)
		KEY_DOWN: change_volume(-VOLUME_STEP)
		KEY_M: toggle_mute()
	# Media keys while focused; when the SMTC helper runs, Windows delivers them through it instead.
	if not media_helper:
		match event.keycode:
			KEY_MEDIAPLAY: toggle_pause()
			KEY_MEDIASTOP: stop_playback()
			KEY_MEDIANEXT: next_track()
			KEY_MEDIAPREVIOUS: previous_track()


func _process(_delta: float) -> void:
	if media_pid < 0:
		return
	while media_udp.get_available_packet_count() > 0:
		var msg := media_udp.get_packet().get_string_from_utf8()
		match msg:
			"hello":
				media_udp.set_dest_address("127.0.0.1", media_udp.get_packet_port())
				media_helper = true
				media_state = ""
				_send_media_title()
			"play":
				if stream_paused or not playing:
					toggle_pause()
			"pause":
				if not stream_paused:
					toggle_pause()
			"stop": stop_playback()
			"next": next_track()
			"previous": previous_track()
			_:
				push_warning("Media keys unavailable: " + msg)
	if media_helper:
		var state := "paused" if stream_paused else ("playing" if playing or not restart_timer.is_stopped() else "stopped")
		if state != media_state:
			media_state = state
			media_udp.put_packet(("state " + state).to_utf8_buffer())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and media_pid >= 0:
		OS.kill(media_pid)


func _start_media_helper() -> void:
	var helper := exe_dir.path_join(MEDIA_HELPER)
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return
	media_udp.bind(0, "127.0.0.1")
	media_pid = OS.create_process(helper, [str(media_udp.get_local_port()), str(OS.get_process_id())])


func _send_media_title() -> void:
	if media_helper and not tracks.is_empty():
		media_udp.put_packet(("title " + tracks[current].get_file().get_basename()).to_utf8_buffer())


## Builds the play order with `first` at the front; shuffled order covers every track once per cycle.
func _build_order(first: int) -> void:
	order.clear()
	for i in tracks.size():
		order.append(i)
	if shuffle:
		order.shuffle()
		if first >= 0:
			order.erase(first)
			order.push_front(first)
		elif order.size() > 1 and order[0] == current:
			# New cycle: avoid repeating the track that just finished.
			order.append(order.pop_front())
	pos = 0 if shuffle else maxi(first, 0)


func _play(index: int) -> void:
	restart_timer.stop()
	current = index
	stream = _load_stream(tracks[current])
	play()
	stream_paused = false
	track_changed.emit(current)
	_send_media_title()


## Manual selection (playlist click): plays that track; in shuffle a new cycle starts from it.
func play_track(index: int) -> void:
	if tracks.is_empty():
		return
	if shuffle:
		_build_order(index)
	else:
		pos = index
	_play(order[pos])


func _step(direction: int, wrap: bool) -> void:
	if tracks.is_empty():
		return
	var p := pos + direction
	if p < 0 or p >= order.size():
		if not wrap:
			stop_playback()
			return
		if shuffle and direction > 0:
			_build_order(-1)
			p = 0
		else:
			p = wrapi(p, 0, order.size())
	pos = p
	_play(order[pos])


func _on_finished() -> void:
	match repeat:
		Repeat.ONE: _play(current)
		Repeat.ALL: _step(1, true)
		Repeat.OFF: _step(1, false)


func next_track() -> void:
	_step(1, true)


func previous_track() -> void:
	_step(-1, true)


func toggle_pause() -> void:
	if not restart_timer.is_stopped():
		return
	if not playing and not stream_paused:
		if not tracks.is_empty():
			_play(current)  # Stopped (e.g. playlist ended with repeat off): start again.
		return
	stream_paused = not stream_paused


func stop_playback() -> void:
	restart_timer.stop()
	stop()
	stream_paused = false


func restart() -> void:
	stop()
	stream_paused = false
	restart_timer.start(RESTART_DELAY)


func seek_by(offset: float) -> void:
	seek_to(get_playback_position() + offset)


func seek_to(pos_seconds: float) -> void:
	# Seeking waits while a restart is pending.
	if stream == null or not restart_timer.is_stopped():
		return
	var was_paused := stream_paused
	play(clampf(pos_seconds, 0.0, stream.get_length()))
	stream_paused = was_paused


func toggle_shuffle() -> void:
	shuffle = not shuffle
	_build_order(current)
	set_app_setting("shuffle", shuffle)


func cycle_repeat() -> void:
	repeat = ((repeat + 1) % 3) as Repeat
	set_app_setting("repeat", repeat)


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	muted = false
	_apply_volume()
	set_app_setting("volume", volume)
	set_app_setting("muted", muted)


func change_volume(step: float) -> void:
	set_volume(volume + step)


func toggle_mute() -> void:
	muted = not muted
	_apply_volume()
	set_app_setting("muted", muted)


## Volume is applied on the Master bus after its effects, so the visualizer still sees the music.
func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, -80.0 if muted or volume <= 0.0 else linear_to_db(volume))


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
