class_name HandOverlay
extends Control

var arm_points: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_arm(points: Array) -> void:
	arm_points = points
	queue_redraw()


func _draw() -> void:
	if arm_points.size() < 3:
		return
	var color := Color("44d9ff")
	draw_line(arm_points[0], arm_points[1], color, 6.0, true)
	draw_line(arm_points[1], arm_points[2], color, 8.0, true)
	draw_circle(arm_points[1], 9.0, color)
	var arm_direction: Vector2 = (arm_points[2] - arm_points[1]).normalized()
	if arm_direction.length_squared() < 0.1:
		arm_direction = Vector2.UP
	var racket_head: Vector2 = arm_points[2] + arm_direction * 42.0
	draw_line(arm_points[2], racket_head - arm_direction * 18.0, Color("c48b55"), 12.0, true)
	draw_circle(racket_head, 31.0, Color(0.12, 0.72, 0.95, 0.82))
	draw_arc(racket_head, 31.0, 0.0, TAU, 40, Color("e8fbff"), 4.0, true)
	draw_circle(arm_points[2], 11.0, Color("fff06a"))
