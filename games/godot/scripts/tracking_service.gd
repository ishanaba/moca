extends Node

const ReplaySourceScript = preload("res://scripts/replay_source.gd")

signal snapshot_updated(players: Array)
signal camera_frame_updated(image: Image)
signal source_changed(label: String)

enum SourceMode { SIMULATED, REPLAY, LIVE }

var source_mode := SourceMode.SIMULATED
var latest_players: Array = []
var _replay := ReplaySourceScript.new()
var _status := "SIMULATED"
var _socket := WebSocketPeer.new()
var _decoder
var _native_sequence := 0
var _video_sequence := 0


func _ready() -> void:
	if ClassDB.can_instantiate("TrackingDecoder"):
		_decoder = ClassDB.instantiate("TrackingDecoder")
	var replay_path := _replay_argument()
	if not replay_path.is_empty():
		start_replay(replay_path)
	var live_url := _live_argument()
	if live_url.is_empty() and OS.has_environment("MOCA_LIVE"):
		live_url = "ws://127.0.0.1:8765"
	if not live_url.is_empty():
		call_deferred("start_live", live_url)


func _process(delta: float) -> void:
	if source_mode == SourceMode.LIVE:
		_poll_live()
		return
	if source_mode == SourceMode.REPLAY:
		latest_players = _replay.advance(delta)
		snapshot_updated.emit(latest_players)
		return
	if source_mode != SourceMode.SIMULATED:
		return
	latest_players = [
		{"id": 1, "blade": get_viewport().get_mouse_position(), "confidence": 1.0, "gripping": true},
	]
	snapshot_updated.emit(latest_players)


func set_source(mode: SourceMode) -> void:
	source_mode = mode
	_status = SourceMode.keys()[mode]
	source_changed.emit(_status)


func start_replay(path := "res://replays/demo.json") -> Error:
	var error := _replay.load_file(path)
	if error != OK:
		_status = "REPLAY ERROR"
		source_changed.emit(_status)
		return error
	set_source(SourceMode.REPLAY)
	return OK


func start_simulation() -> void:
	set_source(SourceMode.SIMULATED)


func start_live(url := "ws://127.0.0.1:8765") -> Error:
	if _decoder == null and ClassDB.can_instantiate("TrackingDecoder"):
		_decoder = ClassDB.instantiate("TrackingDecoder")
	if _decoder == null:
		_status = "LIVE ERROR: NATIVE DECODER"
		source_changed.emit(_status)
		return ERR_UNAVAILABLE
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url(url)
	if error != OK:
		_status = "LIVE ERROR"
		source_changed.emit(_status)
		return error
	_native_sequence = 0
	_video_sequence = 0
	set_source(SourceMode.LIVE)
	_status = "LIVE CONNECTING"
	source_changed.emit(_status)
	return OK


func _poll_live() -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if _status != "LIVE":
			_status = "LIVE"
			source_changed.emit(_status)
		while _socket.get_available_packet_count() > 0:
			_decoder.ingest(_socket.get_packet())
		var video: Dictionary = _decoder.poll_video(_video_sequence)
		if not video.is_empty():
			_video_sequence = int(video.sequence)
			var image := Image.new()
			if image.load_jpg_from_buffer(video.jpeg) == OK:
				camera_frame_updated.emit(image)
		var snapshot: Dictionary = _decoder.poll(_native_sequence)
		if snapshot.is_empty():
			return
		_native_sequence = int(snapshot.sequence)
		var players: Array = []
		for player in snapshot.players:
			players.append({
				"id": int(player.id),
				"blade": Vector2((1.0 - float(player.x)) * 1280.0, float(player.y) * 720.0),
				"confidence": float(player.confidence),
				"gripping": bool(player.gripping),
			})
		latest_players = players
		snapshot_updated.emit(latest_players)
	elif state == WebSocketPeer.STATE_CLOSED and _status != "LIVE CLOSED":
		_status = "LIVE CLOSED"
		source_changed.emit(_status)


func get_status() -> String:
	return _status


func _replay_argument() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument == "--replay":
			return "res://replays/demo.json"
		if argument.begins_with("--replay="):
			return argument.trim_prefix("--replay=")
	return ""


func _live_argument() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument == "--live":
			return "ws://127.0.0.1:8765"
		if argument.begins_with("--live="):
			return argument.trim_prefix("--live=")
	return ""


func get_players() -> Array:
	return latest_players.duplicate(true)
