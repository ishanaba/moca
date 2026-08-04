class_name ReplaySource
extends RefCounted

var duration_seconds := 0.0
var frames: Array[Dictionary] = []
var _elapsed_seconds := 0.0
var _frame_index := 0


func load_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	return load_data(parsed)


func load_data(data: Dictionary) -> Error:
	var input_frames = data.get("frames", [])
	if not input_frames is Array or input_frames.is_empty():
		return ERR_INVALID_DATA
	var parsed_frames: Array[Dictionary] = []
	var previous_time := -1.0
	for input_frame in input_frames:
		if not input_frame is Dictionary:
			return ERR_INVALID_DATA
		var time_seconds := float(input_frame.get("time_ms", -1.0)) / 1000.0
		var input_players = input_frame.get("players", [])
		if time_seconds < 0.0 or time_seconds < previous_time or not input_players is Array:
			return ERR_INVALID_DATA
		var players: Array = []
		for input_player in input_players:
			if not input_player is Dictionary or not input_player.has("id") or not input_player.has("blade"):
				return ERR_INVALID_DATA
			var blade = input_player.blade
			if not blade is Array or blade.size() != 2:
				return ERR_INVALID_DATA
			players.append({
				"id": int(input_player.id),
				"hand_id": int(input_player.get("hand_id", input_player.id)),
				"person_id": int(input_player.get("person_id", 1)),
				"side": str(input_player.get("side", "unknown")),
				"blade": Vector2(float(blade[0]), float(blade[1])),
				"confidence": float(input_player.get("confidence", 1.0)),
			})
		parsed_frames.append({"time": time_seconds, "players": players})
		previous_time = time_seconds
	var default_duration := previous_time + 1.0 / 60.0
	if parsed_frames.size() > 1:
		default_duration = previous_time + previous_time - float(parsed_frames[-2].time)
	var requested_duration := float(data.get("duration_ms", default_duration * 1000.0)) / 1000.0
	if requested_duration <= previous_time:
		return ERR_INVALID_DATA
	frames = parsed_frames
	duration_seconds = requested_duration
	reset()
	return OK


func reset() -> void:
	_elapsed_seconds = 0.0
	_frame_index = 0


func advance(delta: float) -> Array:
	if frames.is_empty():
		return []
	_elapsed_seconds += maxf(delta, 0.0)
	if duration_seconds > 0.0 and _elapsed_seconds >= duration_seconds:
		_elapsed_seconds = fmod(_elapsed_seconds, duration_seconds)
		_frame_index = 0
	while _frame_index + 1 < frames.size() and float(frames[_frame_index + 1].time) <= _elapsed_seconds:
		_frame_index += 1
	return frames[_frame_index].players.duplicate(true)
