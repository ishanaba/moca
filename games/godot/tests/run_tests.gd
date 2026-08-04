extends SceneTree

const GameRulesForTest = preload("res://scripts/game_rules.gd")
const ReplaySourceForTest = preload("res://scripts/replay_source.gd")
const TableTennisRulesForTest = preload("res://scripts/table_tennis_rules.gd")

var failures := 0


func _init() -> void:
	_test_native_extension()
	_test_segment_collision()
	_test_scoring()
	_test_replay()
	_test_table_tennis_mapping()
	if failures == 0:
		print("Godot smoke tests passed")
	quit(failures)


func _test_native_extension() -> void:
	_expect(ClassDB.can_instantiate("TrackingDecoder"), "native TrackingDecoder should load")
	if ClassDB.can_instantiate("TrackingDecoder"):
		var decoder = ClassDB.instantiate("TrackingDecoder")
		_expect(not decoder.ingest(PackedByteArray([1, 2, 3])), "decoder should reject malformed protobuf")
		_expect(decoder.poll(0).is_empty(), "decoder should not publish malformed input")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _test_segment_collision() -> void:
	_expect(GameRulesForTest.segment_hits_circle(Vector2.ZERO, Vector2(10.0, 0.0), Vector2(5.0, 1.0), 2.0), "segment should hit circle")
	_expect(not GameRulesForTest.segment_hits_circle(Vector2.ZERO, Vector2(10.0, 0.0), Vector2(5.0, 5.0), 2.0), "segment should miss distant circle")
	_expect(GameRulesForTest.segment_hits_circle(Vector2(3.0, 3.0), Vector2(3.0, 3.0), Vector2(3.0, 3.0), 1.0), "stationary blade should overlap circle")


func _test_scoring() -> void:
	_expect(GameRulesForTest.score_for_target(false) == 100, "fruit score should be 100")
	_expect(GameRulesForTest.score_for_target(true) == -250, "bomb penalty should be 250")
	_expect(GameRulesForTest.clamp_score(-1) == 0, "score should not become negative")
	_expect(GameRulesForTest.clamp_score(1200) == 1000, "score should be capped at 1000")


func _test_replay() -> void:
	var replay := ReplaySourceForTest.new()
	var error := replay.load_data({
		"duration_ms": 1000,
		"frames": [
			{"time_ms": 0, "players": [{"id": 1, "blade": [10, 20]}]},
			{"time_ms": 500, "players": [{"id": 1, "blade": [30, 40]}]},
		],
	})
	_expect(error == OK, "valid replay should load")
	_expect(replay.advance(0.25)[0].blade == Vector2(10, 20), "replay should hold the current frame")
	_expect(replay.advance(0.25)[0].blade == Vector2(30, 40), "replay should advance at the recorded time")
	_expect(replay.advance(0.5)[0].blade == Vector2(10, 20), "replay should loop deterministically")
	_expect(replay.load_data({"frames": []}) == ERR_INVALID_DATA, "empty replay should be rejected")
	_expect(replay.load_data({"duration_ms": 500, "frames": [{"time_ms": 500, "players": []}]}) == ERR_INVALID_DATA, "duration must extend past the final frame")


func _test_table_tennis_mapping() -> void:
	var center := TableTennisRulesForTest.camera_to_racket(Vector2(640, 360), Vector2(1280, 720), 2.74, 2.15)
	_expect(absf(center.x) < 0.001, "camera center should map to table center")
	_expect(is_equal_approx(center.z, 2.15), "racket should stay on its constrained depth plane")
	var edge := TableTennisRulesForTest.camera_to_racket(Vector2(1280, 720), Vector2(1280, 720), 2.74, 2.15)
	_expect(edge.x > 1.0 and is_equal_approx(edge.y, 1.18), "wrist X should move the racket while height stays fixed")
