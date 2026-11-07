extends AudioStreamPlayer
## TinserBox player: playlist, playback order, queue, settings and Windows media keys.
##
## The playlist is built from the music folder (non-recursive, as before), extra folders
## added by the user (scanned recursively on a worker thread) and individually added or
## dropped files, minus tracks the user removed from the playlist (files are never deleted).
## Per-song settings live in settings.cfg sections keyed by filename.

signal track_changed(index: int)
signal playlist_changed
signal notice(text: String)
signal source_changed

enum Repeat { OFF, ALL, ONE }

const EXTENSIONS := ["mp3", "ogg", "wav"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg"]
const SEEK_STEP := 5.0
const VOLUME_STEP := 0.05
const RESTART_DELAY := 2.0
const APP := "_app"  # App-wide settings; song sections are keyed by filename.
const PLAYLIST := "_playlist"  # Playlist state.
const SORTS := ["name", "name_desc", "artist", "modified"]
const EQ_BANDS := [60.0, 150.0, 400.0, 1000.0, 2400.0, 6000.0, 15000.0]
const EQ21_HZ := [22, 32, 44, 63, 90, 125, 175, 250, 350, 500, 700, 1000, 1400, 2000, 2800, 4000, 5600, 8000, 11000, 16000, 22000]
const MEDIA_HELPER := "TinserBoxMedia.exe"
const MAX_SCAN_FILES := 20000

@onready var audio: Node = $"../Audio"

var exe_dir := OS.get_executable_path().get_base_dir()
var base_dir := _data_dir()
var music_dir := base_dir.path_join("music")
var backgrounds_dir := base_dir.path_join("backgrounds")
var config_path := base_dir.path_join("settings.cfg")
var settings := ConfigFile.new()

var tracks: Array[String] = []  # Current playlist (absolute paths) in display order.
var current := 0
var current_path := ""
var order: Array[int] = []  # Play order (shuffled or sequential); pos indexes into it.
var pos := 0
var queue: Array[String] = []  # Paths to play next, before the normal order.
var library := {}  # path -> true, everything known before filtering.
var folders: Array = []
var extra_files: Array = []
var removed: Array = []
var sort_mode := "name"
var shuffle := false
var repeat := Repeat.ALL
var volume := 1.0
var muted := false
var restart_timer := Timer.new()
var gap_timer := Timer.new()  # Pause between songs after a natural finish.
var song_delay := 0
var _failures := 0
var _save_timer := 0.0
var _scan_task := -1
var _scan_result: Array = []
var _scan_mutex := Mutex.new()
var _meta_cache := {}

# Windows media keys via the SMTC helper (see tools/media_keys).
var media_udp := PacketPeerUDP.new()
var media_pid := -1
var media_helper := false
var media_state := ""
var helper_connected := false  # Helper running (system audio possible), even without media keys.

# System audio: other apps' sound captured by the helper (WASAPI loopback).
var source := "player"  # "player" or "system"
var capture_player := AudioStreamPlayer.new()
var capture_gen := AudioStreamGenerator.new()
var capture_playback: AudioStreamGeneratorPlayback
var _pcm := PackedVector2Array()
var _player_path := ""  # The local track to return to when leaving system audio.
var _want_system := false


## Editor: the project folder. Portable build: next to the executable. Installed build
## (the installer leaves installed.flag next to the exe): Documents\TinserBox.
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
	if first_run and base_dir != exe_dir:
		for folder in ["music", "backgrounds"]:
			for file in DirAccess.get_files_at(exe_dir.path_join(folder)):
				DirAccess.copy_absolute(exe_dir.path_join(folder).path_join(file), base_dir.path_join(folder).path_join(file))
	if FileAccess.file_exists(config_path):
		settings.load(config_path)
	else:
		settings.save(config_path)

	apply_eq()
	shuffle = app_setting("shuffle", false)
	repeat = app_setting("repeat", Repeat.ALL)
	volume = app_setting("volume", 1.0)
	muted = app_setting("muted", false)
	song_delay = app_setting("song_delay", 0)
	_apply_volume()

	restart_timer.one_shot = true
	restart_timer.timeout.connect(func(): play(0.0))
	add_child(restart_timer)
	gap_timer.one_shot = true
	gap_timer.timeout.connect(_advance_after_finish)
	add_child(gap_timer)
	finished.connect(_on_finished)
	get_window().files_dropped.connect(add_paths)

	folders = settings.get_value(PLAYLIST, "folders", [])
	extra_files = settings.get_value(PLAYLIST, "files", [])
	removed = settings.get_value(PLAYLIST, "removed", [])
	sort_mode = settings.get_value(PLAYLIST, "sort", "name")
	for p in settings.get_value(PLAYLIST, "queue", []):
		queue.append(p)

	for file in DirAccess.get_files_at(music_dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			library[music_dir.path_join(file)] = true
	for f in extra_files:
		library[f] = true
	_rebuild("")

	# System audio was the last source: wait for the helper instead of starting a song.
	_want_system = app_setting("audio_source", "player") == "system" and OS.get_name() == "Windows" \
		and FileAccess.file_exists(exe_dir.path_join(MEDIA_HELPER))
	capture_gen.buffer_length = 0.2
	capture_player.stream = capture_gen
	add_child(capture_player)

	# Resume where the user left off, else start fresh (random first track in shuffle).
	var last: String = settings.get_value(PLAYLIST, "last_track", "")
	var last_pos: float = settings.get_value(PLAYLIST, "last_position", 0.0)
	if _want_system:
		current_path = last if last in tracks else ""
		current = maxi(tracks.find(current_path), 0)
	elif last in tracks:
		play_track(tracks.find(last))
		if last_pos > 3.0 and stream and last_pos < stream.get_length() - 5.0:
			seek_to(last_pos)
	elif not tracks.is_empty():
		_build_order(-1)
		_play(order[0])
	if not folders.is_empty():
		_scan_folders()
	_start_media_helper()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.echo and event.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return
	if event.keycode == KEY_Q and event.ctrl_pressed:
		quit_app()
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	if source == "system":
		# Visualizing another app: only window keys apply; its own app controls playback.
		if event.keycode == KEY_F:
			toggle_fullscreen()
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


func _process(delta: float) -> void:
	# Merge a finished background folder scan.
	if _scan_task >= 0 and WorkerThreadPool.is_task_completed(_scan_task):
		WorkerThreadPool.wait_for_task_completion(_scan_task)
		_scan_task = -1
		_scan_mutex.lock()
		var found := _scan_result
		_scan_result = []
		_scan_mutex.unlock()
		for p in found:
			library[p] = true
		_rebuild(current_path)
	# Remember the playback position every few seconds.
	_save_timer += delta
	if _save_timer > 5.0 and playing:
		_save_timer = 0.0
		settings.set_value(PLAYLIST, "last_position", get_playback_position())
		settings.save(config_path)
	_poll_media_helper()


# --- Playlist -----------------------------------------------------------------------

func _rebuild(keep_path: String) -> void:
	var list: Array[String] = []
	for p in library:
		if not (p in removed):
			list.append(p)
	match sort_mode:
		"name_desc":
			list.sort_custom(func(a, b): return a.get_file().naturalnocasecmp_to(b.get_file()) > 0)
		"artist":
			list.sort_custom(func(a, b):
				var c := _artist_of(a).naturalnocasecmp_to(_artist_of(b))
				return c < 0 if c != 0 else a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
		"modified":
			list.sort_custom(func(a, b): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
		_:
			list.sort_custom(func(a, b): return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	tracks = list
	current = tracks.find(keep_path) if keep_path != "" else 0
	if current < 0:
		current = 0
	if shuffle:
		# Keep the existing shuffled cycle when possible: rebuild only if it no longer fits.
		if order.size() != tracks.size():
			_build_order(current)
	else:
		_build_order(current)
	playlist_changed.emit()


func _scan_folders() -> void:
	if _scan_task >= 0:
		return
	var roots := folders.duplicate()
	_scan_task = WorkerThreadPool.add_task(func():
		var found: Array = []
		for root in roots:
			_scan_dir(root, found, 0)
		_scan_mutex.lock()
		_scan_result = found
		_scan_mutex.unlock())


func _scan_dir(dir: String, found: Array, depth: int) -> void:
	if depth > 8 or found.size() >= MAX_SCAN_FILES or not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_scan_dir(dir.path_join(sub), found, depth + 1)


func add_folder(path: String) -> void:
	if path == "" or path in folders:
		return
	folders.append(path)
	settings.set_value(PLAYLIST, "folders", folders)
	settings.save(config_path)
	notice.emit("Adding folder " + path.get_file())
	_scan_folders()


## Drag-and-drop or "add files": folders are scanned, audio files added, others ignored.
func add_paths(paths: PackedStringArray) -> void:
	var added := 0
	for p in paths:
		if DirAccess.dir_exists_absolute(p):
			add_folder(p)
		elif p.get_extension().to_lower() in EXTENSIONS:
			removed.erase(p)
			if not (p in extra_files) and not library.has(p):
				extra_files.append(p)
			library[p] = true
			added += 1
	if added > 0:
		settings.set_value(PLAYLIST, "files", extra_files)
		settings.set_value(PLAYLIST, "removed", removed)
		settings.save(config_path)
		notice.emit("Added %d track%s" % [added, "" if added == 1 else "s"])
		_rebuild(current_path)


## Removes tracks from the playlist only; files stay on disk. Restored if added again.
func remove_tracks(indices: Array) -> void:
	for i in indices:
		if i >= 0 and i < tracks.size():
			var p := tracks[i]
			if not (p in removed):
				removed.append(p)
			queue.erase(p)
	settings.set_value(PLAYLIST, "removed", removed)
	settings.set_value(PLAYLIST, "queue", queue)
	settings.save(config_path)
	_rebuild(current_path)


func set_sort(mode: String) -> void:
	sort_mode = mode if mode in SORTS else "name"
	settings.set_value(PLAYLIST, "sort", sort_mode)
	settings.save(config_path)
	_rebuild(current_path)


func queue_next(index: int) -> void:
	if index >= 0 and index < tracks.size():
		queue.append(tracks[index])
		settings.set_value(PLAYLIST, "queue", queue)
		settings.save(config_path)
		notice.emit("Queued: " + display_name(tracks[index]))
		playlist_changed.emit()


func clear_queue() -> void:
	queue.clear()
	settings.set_value(PLAYLIST, "queue", queue)
	settings.save(config_path)
	playlist_changed.emit()


func display_name(path: String) -> String:
	if path.begins_with("system://"):
		return path.substr(9)
	return path.get_file().get_basename()


func _artist_of(path: String) -> String:
	var n := display_name(path)
	return n.split(" - ")[0] if " - " in n else n


# --- Playback -----------------------------------------------------------------------

## Builds the play order with `first` at the front; a shuffled cycle covers every track once.
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
			order.append(order.pop_front())  # New cycle: never repeat the track that just ended.
	pos = 0 if shuffle else clampi(first, 0, maxi(tracks.size() - 1, 0))


func _play(index: int) -> void:
	restart_timer.stop()
	gap_timer.stop()  # Manual Next/Previous/selection plays immediately.
	if index < 0 or index >= tracks.size():
		return
	current = index
	current_path = tracks[index]
	var s := _load_stream(current_path)
	if s == null or s.get_length() <= 0.0:
		_failures += 1
		notice.emit("Skipped unreadable track: " + display_name(current_path))
		if _failures < tracks.size():
			_step.call_deferred(1, true)
		else:
			stop_playback()
		return
	_failures = 0
	audio.suppress_transients(0.5)
	stream = s
	play()
	stream_paused = false
	settings.set_value(PLAYLIST, "last_track", current_path)
	settings.set_value(PLAYLIST, "last_position", 0.0)
	settings.save(config_path)
	track_changed.emit(current)
	_send_media_title()


## Manual selection: plays that track now; in shuffle a new cycle starts from it.
func play_track(index: int) -> void:
	if tracks.is_empty() or index < 0 or index >= tracks.size():
		return
	if source == "system":
		set_source("player")  # Choosing a local song returns to the TinserBox player.
	if shuffle:
		_build_order(index)
	else:
		pos = index
	_play(order[pos])


func _step(direction: int, wrap: bool) -> void:
	if tracks.is_empty():
		return
	# Queued tracks come first when moving forward.
	while direction > 0 and not queue.is_empty():
		var next_path: String = queue.pop_front()
		settings.set_value(PLAYLIST, "queue", queue)
		var idx := tracks.find(next_path)
		if idx >= 0:
			playlist_changed.emit()
			_play(idx)
			return
	if not shuffle:
		pos = maxi(tracks.find(current_path), 0) if current_path in tracks else pos
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
	if song_delay > 0:
		gap_timer.start(song_delay)
	else:
		_advance_after_finish()


func set_song_delay(seconds: int) -> void:
	song_delay = seconds
	set_app_setting("song_delay", seconds)


func _advance_after_finish() -> void:
	match repeat:
		Repeat.ONE: _play(current)
		Repeat.ALL: _step(1, true)
		Repeat.OFF: _step(1, false)


func next_track() -> void:
	_step(1, true)


func previous_track() -> void:
	_step(-1, true)


func toggle_pause() -> void:
	if not gap_timer.is_stopped():
		gap_timer.stop()  # Pausing during the gap cancels the automatic next song.
		return
	if not restart_timer.is_stopped():
		return
	if not playing and not stream_paused:
		if not tracks.is_empty():
			_play(clampi(current, 0, tracks.size() - 1))
		return
	stream_paused = not stream_paused


func stop_playback() -> void:
	restart_timer.stop()
	gap_timer.stop()
	stop()
	stream_paused = false


func restart() -> void:
	gap_timer.stop()
	stop()
	stream_paused = false
	audio.suppress_transients(2.5)
	restart_timer.start(RESTART_DELAY)


func seek_by(offset: float) -> void:
	seek_to(get_playback_position() + offset)


func seek_to(pos_seconds: float) -> void:
	# Seeking waits while a restart is pending.
	if stream == null or not restart_timer.is_stopped():
		return
	gap_timer.stop()
	audio.suppress_transients(0.4)
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


## Volume is applied on the Master bus after its effects, so the analyzer still sees the music.
func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, -80.0 if muted or volume <= 0.0 else linear_to_db(volume))


func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_state()
		if media_pid >= 0:
			OS.kill(media_pid)


func _save_state() -> void:
	if playing:
		settings.set_value(PLAYLIST, "last_position", get_playback_position())
	settings.set_value(PLAYLIST, "queue", queue)
	settings.save(config_path)


## Quit button / Ctrl+Q: save state, stop playback and close the media-key helper.
func quit_app() -> void:
	_save_state()
	stop_playback()
	if media_pid >= 0:
		OS.kill(media_pid)
	get_tree().quit()


# --- Settings -----------------------------------------------------------------------

func list_backgrounds() -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(backgrounds_dir):
		if file.get_extension().to_lower() in IMAGE_EXTENSIONS:
			files.append(file)
	files.sort()
	return files


## Per-song settings for the current track, keyed by its filename.
func song_setting(key: String, fallback: Variant) -> Variant:
	var section := current_path.get_file()
	return settings.get_value(section, key) if current_path != "" and settings.has_section_key(section, key) else fallback


## Passing null removes the setting.
func set_song_setting(key: String, value: Variant) -> void:
	if current_path != "":
		settings.set_value(current_path.get_file(), key, value)
		settings.save(config_path)


func app_setting(key: String, fallback: Variant) -> Variant:
	return settings.get_value(APP, key) if settings.has_section_key(APP, key) else fallback


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
		audio.eq.set_band_gain_db(i, db)
	var idx: int = audio._effect_index(audio.eq)
	if idx >= 0:
		AudioServer.set_bus_effect_enabled(0, idx, app_setting("eq_enabled", true))


# --- Files and metadata -------------------------------------------------------------

func _load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"mp3":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() < 128:
				return null
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
	return _load_wav(path)


## Minimal PCM WAV reader (8/16-bit); Godot 4.3 has no runtime WAV loader.
func _load_wav(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
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


## Title/artist from ID3v2 tags (MP3), else "Artist - Title" in the filename, else the filename.
func track_info(path: String) -> Dictionary:
	if _meta_cache.has(path):
		return _meta_cache[path]
	var info := {"title": display_name(path), "artist": ""}
	if " - " in info.title:
		var parts: PackedStringArray = info.title.split(" - ", true, 1)
		info = {"title": parts[1], "artist": parts[0]}
	if path.get_extension().to_lower() == "mp3":
		var tags := _read_id3(path)
		if tags.get("TIT2", "") != "":
			info.title = tags.TIT2
		if tags.get("TPE1", "") != "":
			info.artist = tags.TPE1
	_meta_cache[path] = info
	return info


func _read_id3(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 10:
		return out
	var head := f.get_buffer(10)
	if head.slice(0, 3).get_string_from_ascii() != "ID3":
		return out
	var version := head[3]
	var size := (head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9]
	var data := f.get_buffer(mini(size, 262144))
	var i := 0
	while i + 10 <= data.size():
		var id := data.slice(i, i + 4).get_string_from_ascii()
		if id.length() < 4 or id[0] < "A" or id[0] > "Z":
			break
		var fsize := 0
		if version >= 4:
			fsize = (data[i + 4] << 21) | (data[i + 5] << 14) | (data[i + 6] << 7) | data[i + 7]
		else:
			fsize = (data[i + 4] << 24) | (data[i + 5] << 16) | (data[i + 6] << 8) | data[i + 7]
		if fsize <= 0 or i + 10 + fsize > data.size():
			break
		if id == "TIT2" or id == "TPE1":
			out[id] = _decode_text(data.slice(i + 10, i + 10 + fsize))
		i += 10 + fsize
	return out


func _decode_text(frame: PackedByteArray) -> String:
	if frame.is_empty():
		return ""
	var enc := frame[0]
	var body := frame.slice(1)
	# Cut at the terminator: one zero byte, or a zero pair on a UTF-16 boundary.
	var end := body.size()
	if enc == 1 or enc == 2:
		for i in range(0, body.size() - 1, 2):
			if body[i] == 0 and body[i + 1] == 0:
				end = i
				break
	else:
		var z := body.find(0)
		if z >= 0:
			end = z
	body = body.slice(0, end)
	var text := ""
	match enc:
		1, 2:
			text = body.get_string_from_utf16()
		3:
			text = body.get_string_from_utf8()
		_:
			for b in body:  # ISO-8859-1
				text += String.chr(b)
	return text.strip_edges()


# --- Windows media keys -------------------------------------------------------------

func _poll_media_helper() -> void:
	if media_pid < 0:
		return
	while media_udp.get_available_packet_count() > 0:
		var packet := media_udp.get_packet()
		if packet.size() > 1 and packet[0] == 1:
			_push_pcm(packet)
			continue
		var msg := packet.get_string_from_utf8()
		if msg.begins_with("np "):
			var parts := msg.substr(3).split("\t")
			_set_system_track(parts[0], parts[1] if parts.size() > 1 else "")
			continue
		if msg.begins_with("fmt "):
			capture_gen.mix_rate = float(msg.substr(4))
			if source == "system":
				_start_capture_player()
			continue
		match msg:
			"hello", "hello nokeys":
				media_udp.set_dest_address("127.0.0.1", media_udp.get_packet_port())
				helper_connected = true
				media_helper = msg == "hello"
				media_state = ""
				_send_media_title()
				if _want_system:
					_want_system = false
					set_source("system")
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
				push_warning("TinserBox helper: " + msg)
				if msg.begins_with("error capture"):
					notice.emit("System audio capture is unavailable on this device")
	if media_helper and source == "player":
		var state := "paused" if stream_paused else ("playing" if playing or not restart_timer.is_stopped() else "stopped")
		if state != media_state:
			media_state = state
			media_udp.put_packet(("state " + state).to_utf8_buffer())


func _start_media_helper() -> void:
	var helper := exe_dir.path_join(MEDIA_HELPER)
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return
	media_udp.bind(0, "127.0.0.1")
	media_pid = OS.create_process(helper, [str(media_udp.get_local_port()), str(OS.get_process_id())])


# --- System audio -------------------------------------------------------------------

## Switch between TinserBox's own player and visualizing system audio (Windows only).
func set_source(new_source: String) -> bool:
	if new_source == source:
		return true
	if new_source == "system":
		if not helper_connected:
			notice.emit("System audio needs the Windows version (TinserBoxMedia.exe)")
			return false
		_player_path = current_path
		stop_playback()
		source = "system"
		audio.capture_bus()
		_start_capture_player()
		_helper_send("smtc off")
		_helper_send("capture on")
		_set_system_track("", "")
		notice.emit("Visualizing system audio")
	else:
		source = "player"
		if helper_connected:
			_helper_send("capture off")
			_helper_send("smtc on")
		capture_player.stop()
		media_state = ""
		current_path = _player_path if _player_path in tracks else (tracks[0] if not tracks.is_empty() else "")
		current = maxi(tracks.find(current_path), 0)
		track_changed.emit(current)
		notice.emit("TinserBox player")
	audio.set_source(source)
	set_app_setting("audio_source", source)
	source_changed.emit()
	return true


func _helper_send(text: String) -> void:
	if media_pid >= 0 and helper_connected:
		media_udp.put_packet(text.to_utf8_buffer())


func _start_capture_player() -> void:
	capture_player.bus = audio.capture_bus()
	capture_player.stop()
	capture_player.play()
	capture_playback = capture_player.get_stream_playback()


## Captured PCM (int16 stereo after a 1-byte header) into the generator; when the buffer
## is full the packet is dropped, which keeps the delay to the music short.
func _push_pcm(packet: PackedByteArray) -> void:
	if source != "system" or capture_playback == null:
		return
	var frames := (packet.size() - 1) / 4
	if capture_playback.get_frames_available() < frames:
		return
	_pcm.resize(frames)
	for i in frames:
		_pcm[i] = Vector2(packet.decode_s16(1 + i * 4) / 32768.0, packet.decode_s16(3 + i * 4) / 32768.0)
	capture_playback.push_buffer(_pcm)


## The song another app is playing becomes TinserBox's "current song": pop-up, per-song
## looks (section "Artist - Title" in settings.cfg) and automatic atmosphere all apply.
func _set_system_track(title: String, artist: String) -> void:
	var label := title if artist == "" else "%s - %s" % [artist, title]
	label = label.replace("/", "-").replace("\\", "-").strip_edges()
	current_path = "system://" + (label if label != "" else "System audio")
	_meta_cache[current_path] = {"title": title if title != "" else "System audio", "artist": artist}
	track_changed.emit(-1)


func _send_media_title() -> void:
	if media_helper and current_path != "" and source == "player":
		var info := track_info(current_path)
		var text: String = info.title if info.artist == "" else "%s - %s" % [info.artist, info.title]
		media_udp.put_packet(("title " + text).to_utf8_buffer())
