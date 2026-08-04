extends SceneTree

const GameRulesForTest = preload("res://scripts/game_rules.gd")
const ReplaySourceForTest = preload("res://scripts/replay_source.gd")
const TableTennisRulesForTest = preload("res://scripts/table_tennis_rules.gd")
const GardenRulesForTest = preload("res://scripts/garden_rules.gd")

var failures := 0


func _init() -> void:
	_test_native_extension()
	_test_segment_collision()
	_test_scoring()
	_test_replay()
	_test_table_tennis_mapping()
	_test_garden_rules()
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
	_expect(int(replay.advance(0.0)[0].person_id) == 1, "replay hands should retain their child identity")
	_expect(replay.advance(0.5)[0].blade == Vector2(10, 20), "replay should loop deterministically")
	_expect(replay.load_data({"frames": []}) == ERR_INVALID_DATA, "empty replay should be rejected")
	_expect(replay.load_data({"duration_ms": 500, "frames": [{"time_ms": 500, "players": []}]}) == ERR_INVALID_DATA, "duration must extend past the final frame")


func _test_table_tennis_mapping() -> void:
	var center := TableTennisRulesForTest.camera_to_racket(Vector2(640, 360), Vector2(1280, 720), 2.74, 2.15)
	_expect(absf(center.x) < 0.001, "camera center should map to table center")
	_expect(is_equal_approx(center.z, 2.15), "racket should stay on its constrained depth plane")
	var edge := TableTennisRulesForTest.camera_to_racket(Vector2(1280, 720), Vector2(1280, 720), 2.74, 2.15)
	_expect(edge.x > 1.0 and is_equal_approx(edge.y, 1.18), "wrist X should move the racket while height stays fixed")
	var centered_return := TableTennisRulesForTest.hand_return_velocity(0.0, 0.0)
	_expect(centered_return.z < -4.5 and centered_return.y > 2.0, "hand contact should arc toward the computer")
	_expect(TableTennisRulesForTest.hand_return_velocity(0.4, 0.0).x > 0.0, "off-center hand contact should steer the return")
	var moving_return := TableTennisRulesForTest.hand_return_velocity(0.0, 0.0, Vector2(2.0, 1.0))
	_expect(moving_return.x > centered_return.x and moving_return.y > centered_return.y, "hand direction should steer and lift the ball")
	_expect(absf(moving_return.z) > absf(centered_return.z), "a faster hand should produce a faster return")
	var computer_return := TableTennisRulesForTest.computer_return_velocity(0.0, 0.0)
	_expect(computer_return.z >= 5.0 and computer_return.y > 2.3, "computer should return a playable arc toward the player")
	var intercept := TableTennisRulesForTest.predict_intercept(Vector3(0.0, 1.5, 0.0), Vector3(1.0, 2.0, -5.0), -2.0)
	_expect(is_equal_approx(intercept.x, 0.4), "computer should lead the ball horizontally at its baseline")
	_expect(is_equal_approx(intercept.y, 1.516), "computer should account for gravity before interception")
	_expect(is_equal_approx(intercept.z, -2.0), "predicted interception should remain on the racket plane")
	_expect(TableTennisRulesForTest.ball_is_stalled(Vector3(0.0, 1.0, 0.1), Vector3(0.0, 0.2, 0.2)), "slow mid-table ball should be detected as stalled")
	_expect(not TableTennisRulesForTest.ball_is_stalled(Vector3(0.0, 1.0, 1.5), Vector3(0.0, 0.2, -4.0)), "active rally ball should not be detected as stalled")


func _test_garden_rules() -> void:
	_expect(GardenRulesForTest.stage_for_elapsed(0.0) == "welcome", "garden should begin with the welcome")
	_expect(GardenRulesForTest.stage_for_elapsed(15.0) == "seeds", "seed stage should follow the welcome")
	_expect(GardenRulesForTest.stage_for_elapsed(65.0) == "butterflies", "butterfly stage should follow seeds")
	_expect(GardenRulesForTest.stage_for_elapsed(115.0) == "bubbles", "bubble stage should follow butterflies")
	_expect(GardenRulesForTest.stage_for_elapsed(165.0) == "celebration", "garden should end with a celebration")
	_expect(GardenRulesForTest.stage_for_elapsed(180.0) == "complete", "garden should complete at three minutes")
	_expect(GardenRulesForTest.segment_hits_circle(Vector2.ZERO, Vector2(100.0, 0.0), Vector2(50.0, 5.0), 10.0), "fast wrist paths should hit crossed targets")
	var path := [Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0)]
	_expect(GardenRulesForTest.closest_point_on_path(Vector2(45.0, 30.0), path).is_equal_approx(Vector2(45.0, 0.0)), "butterfly guidance should remain inside the maze path")
	var easy := GardenRulesForTest.difficulty_for_history([false, false, true, false])
	var hard := GardenRulesForTest.difficulty_for_history([true, true, true, true, true, true, true, false])
	_expect(float(easy.radius) == 105.0 and float(easy.speed) == 35.0, "low success should make targets larger and slower")
	_expect(float(hard.radius) == 70.0 and float(hard.speed) == 100.0, "high success should make targets smaller and faster")
	var selected := GardenRulesForTest.select_person([
		{"person_id": 1, "confidence": 0.4},
		{"person_id": 1, "confidence": 0.5},
		{"person_id": 2, "confidence": 0.7},
	])
	_expect(selected == 1, "both hands should contribute to child selection")
	var wave := GardenRulesForTest.next_wave_state(0, 0, -1, 700.0, 100)
	wave = GardenRulesForTest.next_wave_state(int(wave.direction), int(wave.switches), int(wave.last_ms), -700.0, 400)
	wave = GardenRulesForTest.next_wave_state(int(wave.direction), int(wave.switches), int(wave.last_ms), 700.0, 700)
	_expect(bool(wave.complete), "three quick direction changes should complete a wave")
	var welcome_wave := GardenRulesForTest.next_wave_state(0, 0, -1, 300.0, 100, 2, 260.0)
	welcome_wave = GardenRulesForTest.next_wave_state(int(welcome_wave.direction), int(welcome_wave.switches), int(welcome_wave.last_ms), -300.0, 450, 2, 260.0)
	_expect(bool(welcome_wave.complete), "a gentle left-right wave should open the garden")
