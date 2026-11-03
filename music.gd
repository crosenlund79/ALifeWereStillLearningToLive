extends AudioStreamPlayer

signal track_changed(index: int)

const MUSIC_DIR := "res://music"
const EXTENSIONS := ["mp3", "ogg", "wav"]
const SEEK_STEP := 5.0
const RESTART_DELAY := 2.0

var tracks: Array[String] = []
var current := 0
var restart_timer := Timer.new()


func _ready() -> void:
	restart_timer.one_shot = true
	restart_timer.timeout.connect(func(): play(0.0))
	add_child(restart_timer)
	finished.connect(next_track)

	for file in DirAccess.get_files_at(MUSIC_DIR):
		# Exported builds only list "track.mp3.import", not the original file.
		var track := file.trim_suffix(".import").trim_suffix(".remap")
		if track.get_extension().to_lower() in EXTENSIONS and track not in tracks:
			tracks.append(track)
	tracks.sort()
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
	stream = load(MUSIC_DIR.path_join(tracks[current]))
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
