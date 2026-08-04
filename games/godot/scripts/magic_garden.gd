extends Node2D

const Rules = preload("res://scripts/garden_rules.gd")
const TargetScript = preload("res://scripts/garden_target.gd")
const SAFE_RECT := Rect2(128.0, 130.0, 1024.0, 460.0)
const TRACKING_TIMEOUT_MS := 250
const TRACKING_STABLE_MS := 500

var camera_view: TextureRect
var camera_texture: ImageTexture
var target: GardenTarget
var instruction_label: Label
var stars_label: Label
var time_label: Label
var tracking_label: Label
var start_button: Button
var pause_button: Button
var replay_button: Button
var running := false
var manually_paused := false
var elapsed := 0.0
var stage := "idle"
var stars := 0
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
		target.set_process(running and not manually_paused and tracking_ready)
	if manually_paused:
		tracking_label.visible = true
		tracking_label.text = "Paused"
		queue_redraw()
		return
	tracking_label.visible = running and not tracking_present
	if running and not tracking_present:
		tracking_label.text = "Come back into view to continue"
	if not running or not tracking_present:
		queue_redraw()
		return
	if not tracking_ready:
		tracking_label.visible = true
		tracking_label.text = "Ready..."
		return
	tracking_label.visible = false
	elapsed += delta
	var next_stage := Rules.stage_for_elapsed(elapsed)
	if next_stage != stage:
		_enter_stage(next_stage)
	if stage == "complete":
		_finish_session()
		return
	if target and target.expired():
		_record_outcome(false)
		_spawn_target()
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
		next_hands[hand_id] = {"point": point, "side": str(observation.get("side", "unknown"))}
		if hands.has(hand_id):
			var old_point: Vector2 = hands[hand_id].point
			_handle_hand_path(old_point, point, now_ms)
	previous_hands = hands
	hands = next_hands
	if not hands.is_empty():
		last_tracking_ms = now_ms
	queue_redraw()


func _handle_hand_path(old_point: Vector2, point: Vector2, now_ms: int) -> void:
	if not running or manually_paused:
		return
	if stage == "butterflies":
		var frame_seconds := maxf(float(now_ms - last_tracking_ms) / 1000.0, 0.001)
		var state := Rules.next_wave_state(wave_direction, wave_switches, wave_last_ms, (point.x - old_point.x) / frame_seconds, now_ms)
		wave_direction = int(state.direction)
		wave_switches = int(state.switches)
		wave_last_ms = int(state.last_ms)
		if bool(state.complete):
			_collect_target()
	elif target and Rules.segment_hits_circle(old_point, point, target.position, target.radius + 24.0):
		_collect_target()


func _collect_target() -> void:
	if target == null:
		return
	stars += 1
	stars_label.text = "★ %d" % stars
	_record_outcome(true)
	_spawn_target()


func _record_outcome(success: bool) -> void:
	outcomes.append(success)
	while outcomes.size() > 8:
		outcomes.pop_front()


func _spawn_target() -> void:
	if target:
		target.queue_free()
		target = null
	if stage not in ["seeds", "butterflies", "bubbles"]:
		return
	var difficulty := Rules.difficulty_for_history(outcomes)
	target = TargetScript.new()
	target.safe_rect = SAFE_RECT
	var margin: float = float(difficulty.radius)
	target.position = Vector2(
		random.randf_range(SAFE_RECT.position.x + margin, SAFE_RECT.end.x - margin),
		random.randf_range(SAFE_RECT.position.y + margin, SAFE_RECT.end.y - margin)
	)
	var direction := Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-0.55, 0.55))
	var speed: float = 0.0 if stage == "seeds" else float(difficulty.speed)
	target.configure("seed" if stage == "seeds" else ("butterfly" if stage == "butterflies" else "bubble"), float(difficulty.radius), speed, direction, float(difficulty.lifetime))
	target.z_index = 5
	add_child(target)


func _enter_stage(next_stage: String) -> void:
	stage = next_stage
	wave_direction = 0
	wave_switches = 0
	wave_last_ms = -1
	var prompts := {
		"welcome": "Wave to wake the garden",
		"seeds": "Touch the glowing seeds",
		"butterflies": "Wave your hand to guide the butterflies",
		"bubbles": "Pop the magic bubbles",
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
	stars = 0
	stage = "idle"
	spoken_stage = ""
	outcomes.clear()
	locked_person_id = 0
	stars_label.text = "★ 0"
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
	stars_label.text = "★ 0"
	pause_button.visible = false
	replay_button.visible = false


func _speak(message: String) -> void:
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(message, str(voices[0]), 65, 1.0, 1.05)


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
	stars_label = Label.new()
	stars_label.position = Vector2(30.0, 25.0)
	stars_label.add_theme_font_size_override("font_size", 32)
	stars_label.add_theme_color_override("font_color", Color("ffe46b"))
	add_child(stars_label)
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
	var flower_count := mini(stars, 28)
	for index in flower_count:
		var x := 55.0 + fmod(float(index * 173), 1170.0)
		var y := 675.0 - float((index * 31) % 54)
		var flower_color := Color.from_hsv(fmod(float(index) * 0.13, 1.0), 0.65, 1.0)
		draw_line(Vector2(x, 710.0), Vector2(x, y), Color("5bd16f"), 7.0, true)
		for petal in 6:
			var angle := float(petal) * TAU / 6.0
			draw_circle(Vector2(x, y) + Vector2.from_angle(angle) * 13.0, 10.0, flower_color)
		draw_circle(Vector2(x, y), 8.0, Color("ffe66d"))
	for hand_value in hands.values():
		var point: Vector2 = hand_value.point
		draw_circle(point, 29.0, Color(1.0, 0.92, 0.3, 0.3))
		draw_arc(point, 32.0, 0.0, TAU, 36, Color("fff6a3"), 6.0, true)
	if stage == "welcome":
		var arrow_color := Color(1.0, 0.95, 0.45, 0.9)
		draw_line(Vector2(480.0, 210.0), Vector2(800.0, 210.0), arrow_color, 10.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(480.0, 210.0), Vector2(520.0, 184.0), Vector2(520.0, 236.0)]), arrow_color)
		draw_colored_polygon(PackedVector2Array([Vector2(800.0, 210.0), Vector2(760.0, 184.0), Vector2(760.0, 236.0)]), arrow_color)
