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
