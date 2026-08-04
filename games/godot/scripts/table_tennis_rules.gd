class_name TableTennisRules
extends RefCounted


static func camera_to_racket(pixel: Vector2, frame_size: Vector2, table_width: float, racket_z: float) -> Vector3:
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return Vector3(0.0, 1.15, racket_z)
	var normalized := Vector2(pixel.x / frame_size.x, pixel.y / frame_size.y)
	var x := lerpf(-table_width * 0.52, table_width * 0.52, normalized.x)
	# The single-camera control is intentionally one-dimensional: wrist X moves
	# the racket across the baseline while height and depth remain stable.
	return Vector3(clampf(x, -table_width * 0.52, table_width * 0.52), 1.18, racket_z)


static func hand_return_velocity(ball_x: float, hand_x: float) -> Vector3:
	var horizontal_offset := clampf((ball_x - hand_x) / 0.36, -1.0, 1.0)
	return Vector3(horizontal_offset * 1.55, 2.55, -5.2)


static func computer_return_velocity(ball_x: float, racket_x: float) -> Vector3:
	var horizontal_offset := clampf((ball_x - racket_x) / 0.36, -1.0, 1.0)
	return Vector3(horizontal_offset * 1.35, 2.45, 5.0)


static func ball_is_stalled(position: Vector3, velocity: Vector3) -> bool:
	return absf(position.z) < 0.7 and absf(velocity.z) < 0.9 and position.y < 1.55
