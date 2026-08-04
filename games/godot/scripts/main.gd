extends Node3D

const Rules = preload("res://scripts/table_tennis_rules.gd")
const HandOverlayScript = preload("res://scripts/hand_overlay.gd")
const TABLE_WIDTH := 2.74
const TABLE_LENGTH := 5.0
const TABLE_HEIGHT := 0.76
const RACKET_Z := 2.15
const HAND_TIMEOUT_MS := 180
const WIN_SCORE := 11

var player_score := 0
var opponent_score := 0
var hand_target := Vector3(0.0, 1.15, RACKET_Z)
var active_hand_id := -1
var hand_detected := false
var last_hand_update_ms := -10000
var serve_toward_player := true
var serve_countdown := 0.0
var last_player_hit_ms := -1000
var stalled_seconds := 0.0
var rally_seconds := 0.0
var last_hitter := "computer"
var receiver_bounces := 0
var event_label: Label
var event_seconds := 0.0
var ball: RigidBody3D
var player_racket: AnimatableBody3D
var player_shape: CollisionShape3D
var opponent_racket: AnimatableBody3D
var score_label: Label
var status_label: Label
var hand_overlay: HandOverlay
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.seed = 0x504f4e47
	_build_world()
	TrackingService.snapshot_updated.connect(_on_snapshot_updated)
	_reset_ball()


func _physics_process(delta: float) -> void:
	if event_seconds > 0.0:
		event_seconds -= delta
		if event_seconds <= 0.0:
			event_label.text = ""
	if Time.get_ticks_msec() - last_hand_update_ms > HAND_TIMEOUT_MS:
		hand_detected = false
		active_hand_id = -1
	_update_player_racket(delta)
	_update_opponent(delta)
	if serve_countdown > 0.0:
		serve_countdown -= delta
		if serve_countdown <= 0.0:
			_launch_ball()
	elif not ball.freeze:
		rally_seconds += delta
		stalled_seconds = stalled_seconds + delta if Rules.ball_is_stalled(ball.position, ball.linear_velocity) else 0.0
		if stalled_seconds > 1.0 or rally_seconds > 15.0:
			serve_toward_player = not serve_toward_player
			_reset_ball()
	_check_point()


func _on_snapshot_updated(players: Array) -> void:
	last_hand_update_ms = Time.get_ticks_msec()
	hand_detected = not players.is_empty()
	if not hand_detected:
		if hand_overlay:
			hand_overlay.set_arm([])
		active_hand_id = -1
		return
	var strongest: Dictionary = players[0]
	var active_found := false
	for observation: Dictionary in players:
		if int(observation.get("id", -1)) == active_hand_id:
			strongest = observation
			active_found = true
			break
		if float(observation.get("confidence", 0.0)) > float(strongest.get("confidence", 0.0)):
			strongest = observation
	if not active_found:
		active_hand_id = int(strongest.get("id", 1))
	if hand_overlay:
		hand_overlay.set_arm(strongest.get("landmarks", []))
	var palm: Vector2 = strongest.get("blade", Vector2(640.0, 360.0))
	hand_target = Rules.camera_to_racket(palm, Vector2(1280.0, 720.0), TABLE_WIDTH, RACKET_Z)


func _update_player_racket(delta: float) -> void:
	player_shape.disabled = not hand_detected
	if not hand_detected:
		status_label.text = "Show your hand"
		return
	status_label.text = "Cover the incoming ball with your hand"
	player_racket.position = player_racket.position.lerp(hand_target, minf(1.0, delta * 18.0))


func _on_ball_body_entered(body: Node) -> void:
	if body == player_racket:
		_on_player_contact()
	elif body == opponent_racket:
		_on_computer_contact()
	elif body.name == "Table":
		_on_table_bounce()
	elif body.name == "Net":
		_show_event("NET")


func _on_player_contact() -> void:
	if not hand_detected or ball.linear_velocity.z <= 0.0:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - last_player_hit_ms < 180:
		return
	last_player_hit_ms = now_ms
	if last_hitter == "computer" and receiver_bounces == 0:
		_award_point("computer", "FOUL — volley before bounce")
		return
	# Depth is not observable with one camera, so contact with the wrist plane
	# creates a deterministic return toward the computer.
	ball.linear_velocity = Rules.hand_return_velocity(ball.position.x, player_racket.position.x)
	var horizontal_offset := ball.linear_velocity.x / 1.8
	ball.angular_velocity = Vector3(0.0, horizontal_offset * 18.0, 0.0)
	last_hitter = "player"
	receiver_bounces = 0
	_show_event("PLAYER HIT")


func _on_computer_contact() -> void:
	if ball.linear_velocity.z >= 0.0:
		return
	if last_hitter == "player" and receiver_bounces == 0:
		_award_point("player", "COMPUTER FOUL")
		return
	ball.linear_velocity = Rules.computer_return_velocity(ball.position.x, opponent_racket.position.x)
	ball.angular_velocity = Vector3(0.0, -ball.linear_velocity.x * 8.0, 0.0)
	last_hitter = "computer"
	receiver_bounces = 0


func _on_table_bounce() -> void:
	var bounce_side := "player" if ball.position.z > 0.0 else "computer"
	var expected_side := "computer" if last_hitter == "player" else "player"
	if receiver_bounces == 0 and bounce_side != expected_side:
		var winner := "computer" if last_hitter == "player" else "player"
		_award_point(winner, "FOUL — wrong-side bounce")
		return
	receiver_bounces += 1
	# Normalize the light ball's first rebound into the receiver's playable
	# zone without allowing repeated rubber-ball hops.
	if receiver_bounces == 1:
		ball.linear_velocity.y = clampf(absf(ball.linear_velocity.y), 1.75, 2.15)
	if receiver_bounces >= 2:
		_award_point(last_hitter, "DOUBLE BOUNCE")


func _show_event(message: String) -> void:
	event_label.text = message
	event_seconds = 1.2


func _award_point(winner: String, reason: String) -> void:
	if winner == "player":
		player_score += 1
		serve_toward_player = true
	else:
		opponent_score += 1
		serve_toward_player = false
	_show_event(reason)
	_reset_ball()


func _update_opponent(delta: float) -> void:
	var target := Vector3(0.0, 1.18, -RACKET_Z)
	var tracking_speed := 5.0
	if not ball.freeze and ball.linear_velocity.z < -0.1:
		var intercept: Vector3 = Rules.predict_intercept(ball.position, ball.linear_velocity, -RACKET_Z)
		target.x = clampf(intercept.x, -1.08, 1.08)
		# Ballistic height is less reliable before the table bounce, so keep the
		# computer inside a plausible ready range instead of snapping vertically.
		target.y = clampf(intercept.y, 0.98, 1.55)
		tracking_speed = 10.0
	opponent_racket.position = opponent_racket.position.lerp(target, minf(1.0, delta * tracking_speed))


func _check_point() -> void:
	if ball.position.z > 3.25 or ball.position.y < -0.5:
		var winner := last_hitter if receiver_bounces > 0 else ("computer" if last_hitter == "player" else "player")
		_award_point(winner, "MISS")
	elif ball.position.z < -3.25:
		var winner := last_hitter if receiver_bounces > 0 else ("computer" if last_hitter == "player" else "player")
		_award_point(winner, "MISS")
	if player_score >= WIN_SCORE or opponent_score >= WIN_SCORE:
		player_score = 0
		opponent_score = 0
	_update_score()


func _reset_ball() -> void:
	ball.position = Vector3(0.0, 1.45, 0.0)
	ball.rotation = Vector3.ZERO
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true
	serve_countdown = 1.25
	stalled_seconds = 0.0
	rally_seconds = 0.0
	receiver_bounces = 0
	_update_score()


func _launch_ball() -> void:
	ball.freeze = false
	ball.sleeping = false
	var direction := 1.0 if serve_toward_player else -1.0
	last_hitter = "computer" if serve_toward_player else "player"
	ball.linear_velocity = Vector3(random.randf_range(-0.55, 0.55), 1.05, direction * 4.4)


func _update_score() -> void:
	if score_label:
		score_label.text = "%d     %d" % [player_score, opponent_score]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("091426")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a8c8ff")
	env.ambient_light_energy = 0.55
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.2, 6.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.8, 0.0))
	add_child(camera)
	var floor_body := _create_static_box("Floor", Vector3(8.0, 0.1, 10.0), Vector3(0.0, -0.1, 0.0), Color("17243a"))
	floor_body.physics_material_override = _material(0.08, 0.45)
	var table_body := _create_static_box("Table", Vector3(TABLE_WIDTH, 0.12, TABLE_LENGTH), Vector3(0.0, TABLE_HEIGHT, 0.0), Color("176b87"))
	table_body.physics_material_override = _material(0.62, 0.23)
	var net_body := _create_static_box("Net", Vector3(TABLE_WIDTH + 0.12, 0.32, 0.035), Vector3(0.0, TABLE_HEIGHT + 0.2, 0.0), Color("e7f5ff"))
	net_body.physics_material_override = _material(0.12, 0.5)
	_create_static_box("CenterLine", Vector3(0.018, 0.008, TABLE_LENGTH), Vector3(0.0, TABLE_HEIGHT + 0.066, 0.0), Color("d9f4ff"), false)
	player_racket = _create_hand_collider(Vector3(0.0, 1.18, RACKET_Z))
	player_shape = player_racket.get_node("CollisionShape3D")
	opponent_racket = _create_racket("OpponentRacket", Color("ff657f"), Vector3(0.0, 1.15, -RACKET_Z))
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = 0.0027
	ball.linear_damp = 0.06
	ball.angular_damp = 0.24
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 8
	ball.physics_material_override = _material(0.56, 0.2)
	var ball_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.04
	ball_shape.shape = sphere
	ball.add_child(ball_shape)
	var ball_mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.09
	sphere_mesh.height = 0.18
	ball_mesh.mesh = sphere_mesh
	var ball_material := _color_material(Color("fff06a"))
	ball_material.emission_enabled = true
	ball_material.emission = Color("ffd83d")
	ball_material.emission_energy_multiplier = 2.5
	ball_mesh.material_override = ball_material
	ball.add_child(ball_mesh)
	add_child(ball)
	ball.body_entered.connect(_on_ball_body_entered)
	var ui := CanvasLayer.new()
	add_child(ui)
	hand_overlay = HandOverlayScript.new()
	ui.add_child(hand_overlay)
	score_label = Label.new()
	score_label.position = Vector2(548.0, 24.0)
	score_label.add_theme_font_size_override("font_size", 42)
	ui.add_child(score_label)
	status_label = Label.new()
	status_label.position = Vector2(28.0, 668.0)
	status_label.add_theme_font_size_override("font_size", 22)
	ui.add_child(status_label)
	event_label = Label.new()
	event_label.position = Vector2(480.0, 88.0)
	event_label.add_theme_font_size_override("font_size", 30)
	event_label.add_theme_color_override("font_color", Color("fff06a"))
	ui.add_child(event_label)


func _create_static_box(name_value: String, size: Vector3, position_value: Vector3, color: Color, collision := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.physics_material_override = _material(0.78, 0.25)
	if collision:
		var collision_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collision_shape.shape = box_shape
		body.add_child(collision_shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _color_material(color)
	body.add_child(mesh_instance)
	add_child(body)
	return body


func _create_racket(name_value: String, color: Color, position_value: Vector3) -> AnimatableBody3D:
	var racket := AnimatableBody3D.new()
	racket.name = name_value
	racket.position = position_value
	racket.physics_material_override = _material(0.92, 0.12)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.64, 0.58, 0.075)
	collision_shape.shape = box_shape
	racket.add_child(collision_shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_shape.size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _color_material(color)
	racket.add_child(mesh_instance)
	add_child(racket)
	return racket


func _create_hand_collider(position_value: Vector3) -> AnimatableBody3D:
	var hand := AnimatableBody3D.new()
	hand.name = "PlayerHandCollider"
	hand.position = position_value
	hand.physics_material_override = _material(1.0, 0.05)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.64, 0.62, 0.12)
	collision_shape.shape = box_shape
	hand.add_child(collision_shape)
	add_child(hand)
	return hand


func _material(bounce: float, friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.bounce = bounce
	material.friction = friction
	return material


func _color_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.15
	material.roughness = 0.42
	return material
