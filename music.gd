extends AudioStreamPlayer

const SEEK_STEP := 5.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_SPACE:
			if not event.echo:
				stream_paused = not stream_paused
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				play(0.0)
				stream_paused = false
		KEY_RIGHT:
			_seek_to(get_playback_position() + SEEK_STEP)
		KEY_LEFT:
			_seek_to(get_playback_position() - SEEK_STEP)


func _seek_to(pos: float) -> void:
	var was_paused := stream_paused
	play(clampf(pos, 0.0, stream.get_length()))
	stream_paused = was_paused
