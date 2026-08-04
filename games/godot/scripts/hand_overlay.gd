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
	draw_circle(arm_points[2], 26.0, Color(1.0, 0.94, 0.42, 0.68))
	draw_arc(arm_points[2], 30.0, 0.0, TAU, 40, Color("e8fbff"), 5.0, true)
