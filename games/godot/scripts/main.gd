extends Node3D

const Rules = preload("res://scripts/table_tennis_rules.gd")
const TABLE_WIDTH := 2.74
const TABLE_LENGTH := 5.0
const TABLE_HEIGHT := 0.76
const RACKET_Z := 2.15
const HAND_TIMEOUT_MS := 180
const WIN_SCORE := 11

var player_score := 0
var opponent_score := 0
var hand_target := Vector3(0.0, 1.15, RACKET_Z)
var hand_detected := false
var hand_gripping := false
var last_hand_update_ms := -10000
var serve_toward_player := true
var ball: RigidBody3D
var player_racket: AnimatableBody3D
var player_shape: CollisionShape3D
var opponent_racket: AnimatableBody3D
var score_label: Label
var status_label: Label
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.seed = 0x504f4e47
	_build_world()
	TrackingService.snapshot_updated.connect(_on_snapshot_updated)
	_reset_ball()


func _physics_process(delta: float) -> void:
	if Time.get_ticks_msec() - last_hand_update_ms > HAND_TIMEOUT_MS:
		hand_detected = false
		hand_gripping = false
	_update_player_racket(delta)
	_update_opponent(delta)
	_check_point()


func _on_snapshot_updated(players: Array) -> void:
	last_hand_update_ms = Time.get_ticks_msec()
	hand_detected = not players.is_empty()
	hand_gripping = false
	if not hand_detected:
		return
	var strongest: Dictionary = players[0]
	for observation: Dictionary in players:
		if float(observation.get("confidence", 0.0)) > float(strongest.get("confidence", 0.0)):
			strongest = observation
	var palm: Vector2 = strongest.get("blade", Vector2(640.0, 360.0))
	hand_target = Rules.camera_to_racket(palm, Vector2(1280.0, 720.0), TABLE_WIDTH, RACKET_Z)
	hand_gripping = bool(strongest.get("gripping", false))


func _update_player_racket(delta: float) -> void:
	player_racket.visible = hand_detected
	player_shape.disabled = not hand_detected or not hand_gripping
	if not hand_detected:
		status_label.text = "Show your hand"
		return
	status_label.text = "GRIP — racket active" if hand_gripping else "Close hand to grip racket"
	var old_position := player_racket.position
	player_racket.position = player_racket.position.lerp(hand_target, minf(1.0, delta * 18.0))
	var velocity := (player_racket.position - old_position) / maxf(delta, 0.001)
	player_racket.rotation.z = clampf(-velocity.x * 0.035, -0.45, 0.45)
	player_racket.rotation.x = clampf(velocity.y * 0.025, -0.35, 0.35)


func _update_opponent(delta: float) -> void:
	var target := Vector3(clampf(ball.position.x, -1.1, 1.1), clampf(ball.position.y, 0.9, 1.75), -RACKET_Z)
	opponent_racket.position = opponent_racket.position.lerp(target, minf(1.0, delta * 5.5))


func _check_point() -> void:
	if ball.position.z > 3.25 or ball.position.y < -0.5:
		opponent_score += 1
		serve_toward_player = false
		_reset_ball()
	elif ball.position.z < -3.25:
		player_score += 1
		serve_toward_player = true
		_reset_ball()
	if player_score >= WIN_SCORE or opponent_score >= WIN_SCORE:
		player_score = 0
		opponent_score = 0
	_update_score()


func _reset_ball() -> void:
	ball.position = Vector3(0.0, 1.45, 0.0)
	ball.rotation = Vector3.ZERO
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = false
	var direction := 1.0 if serve_toward_player else -1.0
	ball.linear_velocity = Vector3(random.randf_range(-0.8, 0.8), 1.4, direction * 4.7)
	_update_score()


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
	_create_static_box("Floor", Vector3(8.0, 0.1, 10.0), Vector3(0.0, -0.1, 0.0), Color("17243a"))
	_create_static_box("Table", Vector3(TABLE_WIDTH, 0.12, TABLE_LENGTH), Vector3(0.0, TABLE_HEIGHT, 0.0), Color("176b87"))
	_create_static_box("Net", Vector3(TABLE_WIDTH + 0.12, 0.32, 0.035), Vector3(0.0, TABLE_HEIGHT + 0.2, 0.0), Color("e7f5ff"))
	_create_static_box("CenterLine", Vector3(0.018, 0.008, TABLE_LENGTH), Vector3(0.0, TABLE_HEIGHT + 0.066, 0.0), Color("d9f4ff"), false)
	player_racket = _create_racket("PlayerRacket", Color("44d9ff"), Vector3(0.0, 1.15, RACKET_Z))
	player_shape = player_racket.get_node("CollisionShape3D")
	opponent_racket = _create_racket("OpponentRacket", Color("ff657f"), Vector3(0.0, 1.15, -RACKET_Z))
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = 0.0027
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 8
	ball.physics_material_override = _material(0.88, 0.15)
	var ball_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	ball_shape.shape = sphere
	ball.add_child(ball_shape)
	var ball_mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.06
	sphere_mesh.height = 0.12
	ball_mesh.mesh = sphere_mesh
	ball_mesh.material_override = _color_material(Color("fff2a8"))
	ball.add_child(ball_mesh)
	add_child(ball)
	var ui := CanvasLayer.new()
	add_child(ui)
	score_label = Label.new()
	score_label.position = Vector2(548.0, 24.0)
	score_label.add_theme_font_size_override("font_size", 42)
	ui.add_child(score_label)
	status_label = Label.new()
	status_label.position = Vector2(28.0, 668.0)
	status_label.add_theme_font_size_override("font_size", 22)
	ui.add_child(status_label)


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
	box_shape.size = Vector3(0.42, 0.52, 0.075)
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
