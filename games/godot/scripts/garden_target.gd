class_name GardenTarget
extends Node2D

var kind := "seed"
var radius := 90.0
var velocity := Vector2.ZERO
var lifetime := 7.0
var age := 0.0
var safe_rect := Rect2(128.0, 130.0, 1024.0, 460.0)


func configure(kind_value: String, radius_value: float, speed: float, direction: Vector2, lifetime_value: float) -> void:
	kind = kind_value
	radius = radius_value
	velocity = direction.normalized() * speed if direction.length_squared() > 0.0 else Vector2.ZERO
	lifetime = lifetime_value
	queue_redraw()


func _process(delta: float) -> void:
	age += delta
	position += velocity * delta
	if position.x - radius < safe_rect.position.x or position.x + radius > safe_rect.end.x:
		velocity.x *= -1.0
		position.x = clampf(position.x, safe_rect.position.x + radius, safe_rect.end.x - radius)
	if kind != "magic_ball" and (position.y - radius < safe_rect.position.y or position.y + radius > safe_rect.end.y):
		velocity.y *= -1.0
		position.y = clampf(position.y, safe_rect.position.y + radius, safe_rect.end.y - radius)
	queue_redraw()


func expired() -> bool:
	return age >= lifetime


func _draw() -> void:
	var pulse := 1.0 + sin(age * 5.0) * 0.06
	if kind == "seed":
		draw_circle(Vector2.ZERO, radius * 0.72 * pulse, Color(1.0, 0.82, 0.2, 0.86))
		draw_circle(Vector2.ZERO, radius * 0.38, Color("8b5a2b"))
		draw_arc(Vector2.ZERO, radius * 0.84, 0.0, TAU, 40, Color("fff6a3"), 7.0, true)
	elif kind == "butterfly":
		var flap := 0.72 + absf(sin(age * 8.0)) * 0.35
		draw_circle(Vector2(-radius * 0.3, 0.0), radius * 0.42 * flap, Color(1.0, 0.35, 0.72, 0.85))
		draw_circle(Vector2(radius * 0.3, 0.0), radius * 0.42 * flap, Color(0.45, 0.85, 1.0, 0.85))
		draw_line(Vector2(0.0, -radius * 0.28), Vector2(0.0, radius * 0.3), Color("34215b"), 8.0, true)
	else:
		draw_circle(Vector2.ZERO, radius * pulse, Color(0.35, 0.85, 1.0, 0.2))
		draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 48, Color(0.72, 0.95, 1.0, 0.92), 7.0, true)
		draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.13, Color(1.0, 1.0, 1.0, 0.75))
		if kind == "magic_ball":
			draw_line(Vector2(0.0, -radius * 1.5), Vector2.ZERO, Color(0.55, 0.9, 1.0, 0.55), 5.0, true)
