extends AudioStreamPlayer

const SEEK_STEP := 5.0
const RESTART_DELAY := 2.0

var restart_timer := Timer.new()


func _ready() -> void:
	restart_timer.one_shot = true
	restart_timer.timeout.connect(func(): play(0.0))
	add_child(restart_timer)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_F:
			if not event.echo:
				var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				stop()
				stream_paused = false
				restart_timer.start(RESTART_DELAY)
	# Playback keys wait while a restart is pending.
	if not restart_timer.is_stopped():
		return
	match event.keycode:
		KEY_SPACE:
			if not event.echo:
				stream_paused = not stream_paused
		KEY_RIGHT:
			_seek_to(get_playback_position() + SEEK_STEP)
		KEY_LEFT:
			_seek_to(get_playback_position() - SEEK_STEP)


func _seek_to(pos: float) -> void:
	var was_paused := stream_paused
	play(clampf(pos, 0.0, stream.get_length()))
	stream_paused = was_paused
