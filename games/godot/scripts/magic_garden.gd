extends Node2D

const Rules = preload("res://scripts/garden_rules.gd")
const TargetScript = preload("res://scripts/garden_target.gd")
const SAFE_RECT := Rect2(128.0, 130.0, 1024.0, 460.0)
const TRACKING_TIMEOUT_MS := 650
const TRACKING_STABLE_MS := 250
const MAZE_TEMPLATES := [
	[Vector2(150.0, 170.0), Vector2(150.0, 390.0), Vector2(390.0, 390.0), Vector2(560.0, 220.0), Vector2(760.0, 420.0), Vector2(1010.0, 420.0)],
	[Vector2(1080.0, 170.0), Vector2(1080.0, 360.0), Vector2(830.0, 360.0), Vector2(650.0, 180.0), Vector2(470.0, 360.0), Vector2(230.0, 360.0)],
	[Vector2(180.0, 180.0), Vector2(430.0, 180.0), Vector2(590.0, 340.0), Vector2(750.0, 180.0), Vector2(1030.0, 180.0), Vector2(1030.0, 450.0)],
]

var camera_view: TextureRect
var camera_texture: ImageTexture
var target: GardenTarget
var seed_targets: Array[GardenTarget] = []
var instruction_label: Label
var flowers_label: Label
var butterflies_label: Label
var time_label: Label
var tracking_label: Label
var start_button: Button
var pause_button: Button
var replay_button: Button
var running := false
var manually_paused := false
var elapsed := 0.0
var stage := "idle"
var butterflies_fed := 0
var locked_person_id := 0
var hands := {}
var previous_hands := {}
var last_tracking_ms := -10000
var tracking_stable_since_ms := -1
var outcomes: Array = []
var random := RandomNumberGenerator.new()
var wave_direction := 0
var wave_switches := 0
var wave_last_ms := -1
var spoken_stage := ""
var collecting := false
var butterfly_segment := 0
var butterfly_segment_progress := 0.0
var butterfly_hand_motion := Vector2.ZERO
var maze_index := 0
var active_maze_path: Array = []
var planted_flowers: Array[Vector2] = []
var spoiled_flowers: Array[Dictionary] = []


func _ready() -> void:
	random.seed = 0x47415244
	_build_ui()
	TrackingService.snapshot_updated.connect(_on_snapshot_updated)
	TrackingService.camera_frame_updated.connect(_on_camera_frame_updated)
	_show_idle()
	if "--autostart" in OS.get_cmdline_user_args():
		call_deferred("_start_session")


func _process(delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	var tracking_present := now_ms - last_tracking_ms <= TRACKING_TIMEOUT_MS and not hands.is_empty()
	if tracking_present:
		if tracking_stable_since_ms < 0:
			tracking_stable_since_ms = now_ms
	else:
		tracking_stable_since_ms = -1
	var tracking_ready := tracking_present and now_ms - tracking_stable_since_ms >= TRACKING_STABLE_MS
	if target:
		target.set_process(running and not manually_paused)
	for seed_target in seed_targets:
		seed_target.set_process(running and not manually_paused and not bool(seed_target.get_meta("caught", false)))
	if manually_paused:
		butterfly_hand_motion = Vector2.ZERO
		tracking_label.visible = true
		tracking_label.text = "Paused"
		queue_redraw()
		return
	tracking_label.visible = running and not tracking_present
	if running and not tracking_present:
		tracking_label.text = "Show your hands inside the frame to continue"
	if not running:
		butterfly_hand_motion = Vector2.ZERO
		queue_redraw()
		return
	if not tracking_present:
		butterfly_hand_motion = Vector2.ZERO
	elif not tracking_ready:
		tracking_label.visible = true
		tracking_label.text = "Ready..."
	else:
		tracking_label.visible = false
	elapsed += delta
	var next_stage := Rules.stage_for_elapsed(elapsed)
	if next_stage != stage:
		_enter_stage(next_stage)
	if stage == "complete":
		_finish_session()
		return
	if stage == "butterflies" and target:
		_update_butterfly()
	if stage == "bubbles" and target:
		_check_magic_ball_damage()
	_update_spoiled_flowers(delta)
	if target and not collecting and target.expired():
		_record_outcome(false)
		_spawn_target()
	if stage == "seeds":
		for seed_target in seed_targets.duplicate():
			if not bool(seed_target.get_meta("caught", false)) and seed_target.expired():
				_record_outcome(false)
				seed_targets.erase(seed_target)
				seed_target.queue_free()
				_spawn_seed()
	time_label.text = "%d:%02d" % [int((Rules.SESSION_END - elapsed) / 60.0), int(Rules.SESSION_END - elapsed) % 60]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()
		elif event.keycode == KEY_R:
			_start_session()


func _on_camera_frame_updated(image: Image) -> void:
	if camera_texture == null:
		camera_texture = ImageTexture.create_from_image(image)
		camera_view.texture = camera_texture
	else:
		camera_texture.update(image)


func _on_snapshot_updated(observations: Array) -> void:
	var now_ms := Time.get_ticks_msec()
	if locked_person_id == 0:
		locked_person_id = Rules.select_person(observations)
	else:
		var locked_person_visible := false
		for observation_value in observations:
			if observation_value is Dictionary and int(observation_value.get("person_id", observation_value.get("id", 0))) == locked_person_id:
				locked_person_visible = true
				break
		if not locked_person_visible and now_ms - last_tracking_ms > TRACKING_TIMEOUT_MS:
			# YOLO identity numbers can change after an occlusion. Reacquire the
			# strongest visible child instead of remaining locked to a stale ID.
			locked_person_id = Rules.select_person(observations)
	var next_hands := {}
	for observation_value in observations:
		if not observation_value is Dictionary:
			continue
		var observation: Dictionary = observation_value
		if locked_person_id > 0 and int(observation.get("person_id", observation.get("id", 0))) != locked_person_id:
			continue
		if float(observation.get("confidence", 0.0)) < 0.15:
			continue
		var hand_id := int(observation.get("hand_id", observation.get("id", 0)))
		var point: Vector2 = observation.get("blade", Vector2.ZERO)
		var tip_direction := Vector2(0.0, -1.0)
		var old_tip := point + tip_direction * 70.0
		if hands.has(hand_id):
			var old_point: Vector2 = hands[hand_id].point
			old_tip = hands[hand_id].get("tip", old_point + Vector2(0.0, -70.0))
			var old_direction: Vector2 = old_tip - old_point
			if old_direction.length_squared() > 0.0:
				tip_direction = old_direction.normalized()
			var movement := point - old_point
			if stage == "butterflies" and movement.length_squared() > butterfly_hand_motion.length_squared():
				butterfly_hand_motion = movement
			if movement.length_squared() > 4.0:
				tip_direction = movement.normalized()
			var tip := point + tip_direction * 70.0
			_handle_hand_path(old_point, point, old_tip, tip, now_ms)
		else:
			old_tip = point + tip_direction * 70.0
		var tip := point + tip_direction * 70.0
		next_hands[hand_id] = {"point": point, "tip": tip, "side": str(observation.get("side", "unknown"))}
	if next_hands.is_empty() and now_ms - last_tracking_ms <= TRACKING_TIMEOUT_MS:
		# Hold the most recent cursor through a short wrist-confidence dropout.
		return
	previous_hands = hands
	hands = next_hands
	if not next_hands.is_empty():
		last_tracking_ms = now_ms
	queue_redraw()


func _handle_hand_path(old_point: Vector2, point: Vector2, old_tip: Vector2, new_tip: Vector2, now_ms: int) -> void:
	if not running or manually_paused:
		return
	if stage == "welcome":
		var frame_seconds := maxf(float(now_ms - last_tracking_ms) / 1000.0, 0.001)
		var required_switches := 2
		var speed_threshold := 260.0
		var state := Rules.next_wave_state(wave_direction, wave_switches, wave_last_ms, (point.x - old_point.x) / frame_seconds, now_ms, required_switches, speed_threshold)
		wave_direction = int(state.direction)
		wave_switches = int(state.switches)
		wave_last_ms = int(state.last_ms)
		if bool(state.complete):
			elapsed = Rules.INTRO_END
			_enter_stage("seeds")
	elif stage == "bubbles" and target:
		if Rules.segment_hits_circle(old_tip, new_tip, target.position, target.radius):
			_collect_target()
	elif stage == "seeds":
		for seed_target in seed_targets:
			if not bool(seed_target.get_meta("caught", false)) and Rules.segment_hits_circle(old_point, point, seed_target.position, seed_target.radius + 24.0):
				_collect_seed(seed_target)
				break


func _collect_target() -> void:
	if target == null or collecting:
		return
	_complete_collection("pop" if stage == "bubbles" else "maze")


func _collect_seed(seed_target: GardenTarget) -> void:
	seed_target.set_meta("caught", true)
	seed_target.set_process(false)
	var bed_position := Vector2(random.randf_range(100.0, 1180.0), 650.0)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(seed_target, "position", bed_position, 0.65)
	tween.tween_property(seed_target, "scale", Vector2(0.35, 0.35), 0.65)
	tween.chain().tween_callback(_finish_seed_collection.bind(seed_target, bed_position))


func _finish_seed_collection(seed_target: GardenTarget, bed_position: Vector2) -> void:
	if not is_instance_valid(seed_target):
		return
	seed_targets.erase(seed_target)
	seed_target.queue_free()
	planted_flowers.append(bed_position)
	_play_tone(520.0, 0.22)
	_play_tone(720.0, 0.28)
	_record_outcome(true)
	_update_counters()
	if stage == "seeds":
		_spawn_seed()


func _complete_collection(sound_kind: String) -> void:
	if target == null:
		return
	if sound_kind == "pop":
		_play_tone(900.0, 0.11)
	elif sound_kind == "maze":
		butterflies_fed += 1
		maze_index += 1
	_update_counters()
	_record_outcome(true)
	collecting = false
	_spawn_target()


func _record_outcome(success: bool) -> void:
	outcomes.append(success)
	while outcomes.size() > 8:
		outcomes.pop_front()


func _spawn_target() -> void:
	if target:
		target.queue_free()
	target = null
	for seed_target in seed_targets:
		seed_target.queue_free()
	seed_targets.clear()
	collecting = false
	if stage not in ["seeds", "butterflies", "bubbles"]:
		return
	if stage == "seeds":
		_spawn_seed()
		_spawn_seed()
		return
	var difficulty := Rules.difficulty_for_history(outcomes)
	if stage == "butterflies":
		active_maze_path = _make_maze_path()
	target = TargetScript.new()
	target.safe_rect = SAFE_RECT
	var margin: float = float(difficulty.radius)
	target.position = active_maze_path[0] if stage == "butterflies" else Vector2(
		random.randf_range(SAFE_RECT.position.x + margin, SAFE_RECT.end.x - margin),
		random.randf_range(SAFE_RECT.position.y + margin, SAFE_RECT.end.y - margin)
	)
	var direction := Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-0.55, 0.55))
	var speed: float = 0.0 if stage == "seeds" else float(difficulty.speed)
	var target_radius: float = 36.0 if stage == "butterflies" else float(difficulty.radius)
	var target_lifetime: float = 999.0 if stage == "butterflies" else float(difficulty.lifetime)
	var target_kind := "butterfly" if stage == "butterflies" else "magic_ball"
	if stage == "bubbles":
		var target_x := random.randf_range(180.0, 1100.0)
		if not planted_flowers.is_empty():
			target_x = planted_flowers[random.randi_range(0, planted_flowers.size() - 1)].x
		target.position = Vector2(target_x, 95.0)
		direction = Vector2.DOWN
		speed = random.randf_range(72.0, 105.0)
		target_lifetime = 9.0
	target.configure(target_kind, target_radius, speed, direction, target_lifetime)
	target.z_index = 5
	add_child(target)
	if stage == "butterflies":
		butterfly_segment = 0
		butterfly_segment_progress = 0.0
		butterfly_hand_motion = Vector2.ZERO


func _spawn_seed() -> void:
	var difficulty := Rules.difficulty_for_history(outcomes)
	var seed := TargetScript.new()
	seed.safe_rect = SAFE_RECT
	var radius: float = float(difficulty.radius)
	seed.position = Vector2(
		random.randf_range(SAFE_RECT.position.x + radius, SAFE_RECT.end.x - radius),
		random.randf_range(SAFE_RECT.position.y + radius, SAFE_RECT.end.y - radius)
	)
	seed.configure("seed", radius, 0.0, Vector2.ZERO, float(difficulty.lifetime))
	seed.z_index = 5
	seed_targets.append(seed)
	add_child(seed)


func _make_maze_path() -> Array:
	var path: Array = MAZE_TEMPLATES[maze_index % MAZE_TEMPLATES.size()].duplicate()
	var flower_position := Vector2(640.0, 650.0)
	if not planted_flowers.is_empty():
		flower_position = planted_flowers[maze_index % planted_flowers.size()]
	# The corridor stays above the established flower bed until its final
	# vertical/diagonal approach into the selected planted flower.
	path.append(Vector2(flower_position.x, 510.0))
	path.append(flower_position)
	return path


func _check_magic_ball_damage() -> void:
	for index in planted_flowers.size():
		if target.position.distance_to(planted_flowers[index]) <= target.radius + 28.0:
			spoiled_flowers.append({"position": planted_flowers[index], "age": 0.0})
			planted_flowers.remove_at(index)
			_play_tone(260.0, 0.3)
			_play_tone(180.0, 0.38)
			_record_outcome(false)
			_update_counters()
			_spawn_target()
			return


func _update_spoiled_flowers(delta: float) -> void:
	for index in range(spoiled_flowers.size() - 1, -1, -1):
		var spoiled: Dictionary = spoiled_flowers[index]
		spoiled.age = float(spoiled.age) + delta
		if float(spoiled.age) > 1.6:
			spoiled_flowers.remove_at(index)
		else:
			spoiled_flowers[index] = spoiled


func _update_counters() -> void:
	flowers_label.text = "Flowers planted: %d" % planted_flowers.size()
	butterflies_label.text = "Butterflies fed: %d" % butterflies_fed


func _update_butterfly() -> void:
	if butterfly_segment >= active_maze_path.size() - 1:
		_complete_collection("maze")
		return
	var start: Vector2 = active_maze_path[butterfly_segment]
	var finish: Vector2 = active_maze_path[butterfly_segment + 1]
	var segment := finish - start
	# Incorrect movement is consumed without moving. Matching vertical,
	# horizontal, or diagonal movement advances along the current corridor.
	if Rules.movement_matches_path(butterfly_hand_motion, segment):
		butterfly_segment_progress += minf(butterfly_hand_motion.length() * 1.15, 48.0)
	butterfly_hand_motion = Vector2.ZERO
	while butterfly_segment_progress >= segment.length():
		butterfly_segment_progress -= segment.length()
		butterfly_segment += 1
		if butterfly_segment >= active_maze_path.size() - 1:
			target.position = active_maze_path[-1]
			_complete_collection("maze")
			return
		start = active_maze_path[butterfly_segment]
		finish = active_maze_path[butterfly_segment + 1]
		segment = finish - start
	target.position = start + segment.normalized() * butterfly_segment_progress


func _enter_stage(next_stage: String) -> void:
	stage = next_stage
	if stage == "butterflies":
		maze_index = 0
	wave_direction = 0
	wave_switches = 0
	wave_last_ms = -1
	var prompts := {
		"welcome": "Wave to wake the garden",
		"seeds": "Touch the glowing seeds",
		"butterflies": "Move your hand in the path direction to guide the butterfly",
		"bubbles": "Pop falling magic balls before they spoil the flowers",
		"celebration": "Look — the garden is growing!",
	}
	instruction_label.text = str(prompts.get(stage, "Great job!"))
	if spoken_stage != stage:
		_speak(instruction_label.text)
		spoken_stage = stage
	_spawn_target()


func _start_session() -> void:
	running = true
	manually_paused = false
	elapsed = 0.0
	butterflies_fed = 0
	planted_flowers.clear()
	spoiled_flowers.clear()
	maze_index = 0
	stage = "idle"
	spoken_stage = ""
	outcomes.clear()
	locked_person_id = 0
	_update_counters()
	start_button.visible = false
	pause_button.visible = true
	replay_button.visible = false
	pause_button.text = "Pause"
	_enter_stage("welcome")


func _toggle_pause() -> void:
	if not running:
		return
	manually_paused = not manually_paused
	pause_button.text = "Resume" if manually_paused else "Pause"
	tracking_label.visible = manually_paused
	tracking_label.text = "Paused"


func _finish_session() -> void:
	running = false
	if target:
		target.queue_free()
		target = null
	instruction_label.text = "Great job! You grew a magical garden!"
	_speak("Great job!")
	pause_button.visible = false
	replay_button.visible = true


func _show_idle() -> void:
	instruction_label.text = "Magic Garden Rescue"
	time_label.text = "3:00"
	_update_counters()
	pause_button.visible = false
	replay_button.visible = false


func _speak(message: String) -> void:
	# Some Linux/Flatpak builds advertise TTS while their synthesizer is null.
	# Keep speech opt-in until a working system voice has been configured.
	if not OS.has_environment("MOCA_ENABLE_TTS") or not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(message, str(voices[0]), 65, 1.0, 1.05)


func _play_tone(frequency: float, duration: float) -> void:
	var sample_rate := 22050
	var sample_count := int(float(sample_rate) * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in sample_count:
		var envelope := 1.0 - float(index) / float(sample_count)
		var sample := int(sin(TAU * frequency * float(index) / float(sample_rate)) * 12000.0 * envelope)
		data.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _build_ui() -> void:
	camera_view = TextureRect.new()
	camera_view.position = Vector2.ZERO
	camera_view.size = Vector2(1280.0, 720.0)
	camera_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	camera_view.flip_h = true
	camera_view.modulate = Color(0.78, 0.9, 0.82)
	camera_view.z_index = -20
	add_child(camera_view)
	var tint := ColorRect.new()
	tint.position = Vector2.ZERO
	tint.size = Vector2(1280.0, 720.0)
	tint.color = Color(0.04, 0.16, 0.09, 0.22)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.z_index = -10
	add_child(tint)
	instruction_label = Label.new()
	instruction_label.position = Vector2(180.0, 28.0)
	instruction_label.size = Vector2(920.0, 72.0)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 34)
	instruction_label.add_theme_color_override("font_color", Color("fff7b2"))
	add_child(instruction_label)
	flowers_label = Label.new()
	flowers_label.position = Vector2(24.0, 20.0)
	flowers_label.add_theme_font_size_override("font_size", 25)
	flowers_label.add_theme_color_override("font_color", Color("ffe46b"))
	add_child(flowers_label)
	butterflies_label = Label.new()
	butterflies_label.position = Vector2(24.0, 55.0)
	butterflies_label.add_theme_font_size_override("font_size", 23)
	butterflies_label.add_theme_color_override("font_color", Color("ffb8e5"))
	add_child(butterflies_label)
	time_label = Label.new()
	time_label.position = Vector2(1160.0, 28.0)
	time_label.add_theme_font_size_override("font_size", 26)
	add_child(time_label)
	tracking_label = Label.new()
	tracking_label.position = Vector2(340.0, 315.0)
	tracking_label.size = Vector2(600.0, 80.0)
	tracking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracking_label.add_theme_font_size_override("font_size", 30)
	tracking_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(tracking_label)
	start_button = _make_button("Start Garden", Vector2(535.0, 610.0), _start_session)
	pause_button = _make_button("Pause", Vector2(25.0, 650.0), _toggle_pause)
	replay_button = _make_button("Play Again", Vector2(535.0, 610.0), _start_session)


func _make_button(label_text: String, button_position: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.position = button_position
	button.size = Vector2(210.0, 58.0)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(callback)
	add_child(button)
	return button


func _draw() -> void:
	# Garden progress grows along the bottom without obscuring the child.
	draw_rect(Rect2(0.0, 590.0, 1280.0, 130.0), Color(0.05, 0.32, 0.14, 0.72))
	for index in planted_flowers.size():
		var x := planted_flowers[index].x
		var y := planted_flowers[index].y
		var flower_color := Color.from_hsv(fmod(float(index) * 0.13, 1.0), 0.65, 1.0)
		draw_line(Vector2(x, 710.0), Vector2(x, y), Color("5bd16f"), 7.0, true)
		for petal in 6:
			var angle := float(petal) * TAU / 6.0
			draw_circle(Vector2(x, y) + Vector2.from_angle(angle) * 13.0, 10.0, flower_color)
		draw_circle(Vector2(x, y), 8.0, Color("ffe66d"))
	for spoiled_value in spoiled_flowers:
		var spoiled: Dictionary = spoiled_value
		var point: Vector2 = spoiled.position
		var fade := 1.0 - clampf(float(spoiled.age) / 1.6, 0.0, 1.0)
		var bad_color := Color(0.35, 0.2, 0.12, fade)
		draw_line(Vector2(point.x, 710.0), point + Vector2(12.0, 15.0), bad_color, 7.0, true)
		for petal in 5:
			var angle := float(petal) * TAU / 5.0
			draw_circle(point + Vector2(12.0, 15.0) + Vector2.from_angle(angle) * 11.0, 9.0, bad_color)
	if stage == "butterflies" and not active_maze_path.is_empty():
		draw_polyline(PackedVector2Array(active_maze_path), Color(0.12, 0.08, 0.24, 0.9), 130.0, true)
		draw_polyline(PackedVector2Array(active_maze_path), Color(0.55, 0.9, 0.55, 0.48), 100.0, true)
		draw_circle(active_maze_path[0], 38.0, Color(0.35, 0.9, 0.55, 0.9))
		draw_circle(active_maze_path[-1], 45.0, Color(1.0, 0.82, 0.2, 0.45))
		draw_string(ThemeDB.fallback_font, active_maze_path[0] + Vector2(-38.0, 8.0), "START", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(560.0, 115.0), "MAZE %d" % (maze_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color("fff6a3"))
		if target and butterfly_segment < active_maze_path.size() - 1:
			var path_direction: Vector2 = (active_maze_path[butterfly_segment + 1] - active_maze_path[butterfly_segment]).normalized()
			var arrow_end := target.position + path_direction * 68.0
			draw_line(target.position, arrow_end, Color("fff06a"), 9.0, true)
			var arrow_side := path_direction.rotated(PI * 0.5) * 13.0
			draw_colored_polygon(PackedVector2Array([arrow_end + path_direction * 12.0, arrow_end - path_direction * 18.0 + arrow_side, arrow_end - path_direction * 18.0 - arrow_side]), Color("fff06a"))
	for hand_value in hands.values():
		var point: Vector2 = hand_value.point
		if stage == "seeds":
			# An open scoop replaces the generic hand circle for catching seeds.
			draw_line(point + Vector2(0.0, -5.0), point + Vector2(0.0, -70.0), Color("d9f6ff"), 10.0, true)
			draw_arc(point, 34.0, 0.0, PI, 24, Color("fff06a"), 10.0, true)
		elif stage == "butterflies":
			var wind_direction := Vector2.RIGHT
			if target and butterfly_segment < active_maze_path.size() - 1:
				wind_direction = (active_maze_path[butterfly_segment + 1] - active_maze_path[butterfly_segment]).normalized()
			var wind_side := wind_direction.rotated(PI * 0.5)
			for offset in [-18.0, 0.0, 18.0]:
				draw_line(point - wind_direction * 48.0 + wind_side * offset, point + wind_direction * 42.0 + wind_side * offset, Color(0.65, 0.95, 1.0, 0.82), 6.0, true)
		elif stage == "bubbles":
			var tip: Vector2 = hand_value.get("tip", point + Vector2(0.0, -70.0))
			draw_line(point, tip, Color("d9f6ff"), 10.0, true)
			var direction := (tip - point).normalized()
			var side := direction.rotated(PI * 0.5) * 10.0
			draw_colored_polygon(PackedVector2Array([tip + direction * 15.0, tip - direction * 12.0 + side, tip - direction * 12.0 - side]), Color("fff06a"))
		else:
			draw_circle(point, 29.0, Color(1.0, 0.92, 0.3, 0.3))
			draw_arc(point, 32.0, 0.0, TAU, 36, Color("fff6a3"), 6.0, true)
	if stage == "welcome":
		var arrow_color := Color(1.0, 0.95, 0.45, 0.9)
		draw_line(Vector2(480.0, 210.0), Vector2(800.0, 210.0), arrow_color, 10.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(480.0, 210.0), Vector2(520.0, 184.0), Vector2(520.0, 236.0)]), arrow_color)
		draw_colored_polygon(PackedVector2Array([Vector2(800.0, 210.0), Vector2(760.0, 184.0), Vector2(760.0, 236.0)]), arrow_color)
