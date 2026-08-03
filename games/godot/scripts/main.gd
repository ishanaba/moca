extends Node2D

const GameRulesScript = preload("res://scripts/game_rules.gd")

const RECORD_PATH := "user://moca_records.cfg"
const TARGET_RADIUS := 30.0
const BLADE_RADIUS := 13.0
const SPAWN_INTERVAL := 0.75
const TARGET_LIFETIME := 9.0
const TARGET_SPEED_MIN := 130.0
const TARGET_SPEED_MAX := 280.0
const SMOOTH_ALPHA_MIN := 0.22
const SMOOTH_ALPHA_MAX := 0.82
const FAST_MOTION_PIXELS := 180.0
const COLORS := [Color("55d6ff"), Color("ff70d2")]
const HIT_SOUND_PLAYERS := 4

var scores := [0]
var elapsed_time := 0.0
var best_time := -1.0
var new_record := false
var spawn_left := 0.15
var previous_blades := [Vector2(590.0, 360.0), Vector2(690.0, 360.0)]
var blades := [Vector2(590.0, 360.0), Vector2(690.0, 360.0)]
var targets: Array[Dictionary] = []
var round_over := false
var random := RandomNumberGenerator.new()
var camera_texture: ImageTexture
var blade_acquired := [false, false]
var hit_sound_players: Array[AudioStreamPlayer] = []
var next_hit_sound_player := 0


func _ready() -> void:
	random.seed = 0x4d4f4341
	_load_record()
	_create_hit_sound_players()
	TrackingService.snapshot_updated.connect(_on_snapshot_updated)
	TrackingService.camera_frame_updated.connect(_on_camera_frame_updated)
	TrackingService.source_changed.connect(func(_label: String) -> void: queue_redraw())
	queue_redraw()


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_F1) and TrackingService.source_mode != TrackingService.SourceMode.SIMULATED:
		TrackingService.start_simulation()
	if Input.is_key_pressed(KEY_F2) and TrackingService.source_mode != TrackingService.SourceMode.REPLAY:
		TrackingService.start_replay()
	if Input.is_key_pressed(KEY_F3) and TrackingService.source_mode != TrackingService.SourceMode.LIVE:
		TrackingService.start_live()
	if round_over:
		if Input.is_action_just_pressed("ui_accept"):
			_reset_round()
		queue_redraw()
		return
	elapsed_time += delta
	spawn_left -= delta
	if spawn_left <= 0.0:
		_spawn_target()
		spawn_left += SPAWN_INTERVAL
	_update_targets(delta)
	_check_hits()
	queue_redraw()


func _on_snapshot_updated(players: Array) -> void:
	if players.is_empty():
		return
	previous_blades = blades.duplicate()
	# This game is intentionally one-player. Tracker IDs identify tracks, not
	# player slots, and may change after a temporary detection loss. Always map
	# the strongest current observation to slot zero so tracking can recover.
	var observations := players.duplicate()
	observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("confidence", 0.0)) > float(b.get("confidence", 0.0)))
	for observation_index in mini(observations.size(), blades.size()):
		var observation: Dictionary = observations[observation_index]
		var hand_id: int = int(observation.get("id", observation_index + 1))
		var slot: int = (hand_id - 1) % blades.size()
		var measured: Vector2 = observation.get("blade", blades[slot])
		if not blade_acquired[slot]:
			blades[slot] = measured
			previous_blades[slot] = measured
			blade_acquired[slot] = true
			continue
		var distance: float = blades[slot].distance_to(measured)
		var motion: float = clampf(distance / FAST_MOTION_PIXELS, 0.0, 1.0)
		var alpha: float = lerpf(SMOOTH_ALPHA_MIN, SMOOTH_ALPHA_MAX, motion)
		blades[slot] = blades[slot].lerp(measured, alpha)


func _on_camera_frame_updated(image: Image) -> void:
	if camera_texture == null:
		camera_texture = ImageTexture.create_from_image(image)
	else:
		camera_texture.update(image)
	queue_redraw()


func _spawn_target() -> void:
	var angle := random.randf_range(0.0, TAU)
	var speed := random.randf_range(TARGET_SPEED_MIN, TARGET_SPEED_MAX)
	targets.append({
		"position": Vector2(random.randf_range(70.0, 1210.0), random.randf_range(100.0, 650.0)),
		"velocity": Vector2.from_angle(angle) * speed,
		"bomb": random.randf() < 0.18,
		"age": 0.0,
	})


func _update_targets(delta: float) -> void:
	for target in targets:
		target.age += delta
		target.position += target.velocity * delta
		if target.position.x < TARGET_RADIUS:
			target.position.x = TARGET_RADIUS
			target.velocity.x = absf(target.velocity.x)
		elif target.position.x > 1280.0 - TARGET_RADIUS:
			target.position.x = 1280.0 - TARGET_RADIUS
			target.velocity.x = -absf(target.velocity.x)
		if target.position.y < 76.0:
			target.position.y = 76.0
			target.velocity.y = absf(target.velocity.y)
		elif target.position.y > 720.0 - TARGET_RADIUS:
			target.position.y = 720.0 - TARGET_RADIUS
			target.velocity.y = -absf(target.velocity.y)
	targets = targets.filter(func(target: Dictionary) -> bool: return float(target.age) < TARGET_LIFETIME)


func _check_hits() -> void:
	for target in targets.duplicate():
		for player_index in blades.size():
			if GameRulesScript.segment_hits_circle(previous_blades[player_index], blades[player_index], target.position, TARGET_RADIUS + BLADE_RADIUS):
				if not target.bomb:
					_play_fruit_hit_sound()
				scores[0] = GameRulesScript.clamp_score(scores[0] + GameRulesScript.score_for_target(target.bomb))
				targets.erase(target)
				if scores[0] >= GameRulesScript.MAX_SCORE:
					_finish_round()
					return
				break


func _create_hit_sound_players() -> void:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 44100
	sound.stereo = false
	var duration := 0.13
	var sample_count := int(sound.mix_rate * duration)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for sample_index in sample_count:
		var time := float(sample_index) / float(sound.mix_rate)
		var envelope := pow(1.0 - time / duration, 2.0)
		var frequency := lerpf(880.0, 1320.0, time / duration)
		var sample := sin(TAU * frequency * time) * envelope * 0.32
		pcm.encode_s16(sample_index * 2, int(sample * 32767.0))
	sound.data = pcm
	for index in HIT_SOUND_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.name = "FruitHitSound%d" % index
		player.stream = sound
		player.volume_db = -4.0
		add_child(player)
		hit_sound_players.append(player)


func _play_fruit_hit_sound() -> void:
	if hit_sound_players.is_empty():
		return
	var player := hit_sound_players[next_hit_sound_player]
	next_hit_sound_player = (next_hit_sound_player + 1) % hit_sound_players.size()
	player.play()


func _finish_round() -> void:
	if round_over:
		return
	round_over = true
	new_record = best_time < 0.0 or elapsed_time < best_time
	if new_record:
		best_time = elapsed_time
		var config := ConfigFile.new()
		config.set_value("time_attack", "best_seconds", best_time)
		config.save(RECORD_PATH)


func _load_record() -> void:
	var config := ConfigFile.new()
	if config.load(RECORD_PATH) == OK:
		best_time = float(config.get_value("time_attack", "best_seconds", -1.0))


func _reset_round() -> void:
	scores = [0]
	elapsed_time = 0.0
	spawn_left = 0.15
	targets.clear()
	round_over = false
	new_record = false
	random.seed = 0x4d4f4341


func _draw() -> void:
	if camera_texture != null:
		draw_set_transform(Vector2(1280.0, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(camera_texture, Rect2(0.0, 0.0, 1280.0, 720.0), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.01, 0.03, 0.08, 0.28))
	else:
		draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color("07101f"))
	for target in targets:
		var color := Color("ff4057") if target.bomb else Color("8ee85b")
		draw_circle(target.position, TARGET_RADIUS, color)
		if target.bomb:
			draw_line(target.position - Vector2(10.0, 10.0), target.position + Vector2(10.0, 10.0), Color.WHITE, 4.0)
			draw_line(target.position + Vector2(10.0, -10.0), target.position + Vector2(-10.0, 10.0), Color.WHITE, 4.0)
	for index in blades.size():
		draw_line(previous_blades[index], blades[index], COLORS[index], 8.0, true)
		draw_circle(blades[index], BLADE_RADIUS, COLORS[index])
	_draw_text()


func _draw_text() -> void:
	var font := ThemeDB.fallback_font
	var large := 32
	draw_string(font, Vector2(40.0, 52.0), "SCORE  %04d / 1000" % scores[0], HORIZONTAL_ALIGNMENT_LEFT, -1.0, large, COLORS[0])
	draw_string(font, Vector2(540.0, 52.0), "TIME  %.2f" % elapsed_time, HORIZONTAL_ALIGNMENT_LEFT, -1.0, large, Color.WHITE)
	var record_text := "RECORD  --" if best_time < 0.0 else "RECORD  %.2f" % best_time
	draw_string(font, Vector2(930.0, 52.0), record_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color("ffd166"))
	draw_string(font, Vector2(32.0, 700.0), "F1 Simulation    F2 Replay    F3 Live    Source: %s" % TrackingService.get_status(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("a9bad3"))
	if round_over:
		draw_rect(Rect2(330.0, 270.0, 620.0, 160.0), Color(0.02, 0.03, 0.07, 0.92), true)
		var title := "NEW RECORD!" if new_record else "1000 POINTS!"
		draw_string(font, Vector2(475.0, 325.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, Color("ffd166"))
		draw_string(font, Vector2(475.0, 365.0), "Time: %.2f seconds" % elapsed_time, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color.WHITE)
		draw_string(font, Vector2(475.0, 405.0), "Press Space to play again", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color("a9bad3"))
