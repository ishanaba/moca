class_name TableTennisRules
extends RefCounted


static func camera_to_racket(pixel: Vector2, frame_size: Vector2, table_width: float, racket_z: float) -> Vector3:
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return Vector3(0.0, 1.15, racket_z)
	var normalized := Vector2(pixel.x / frame_size.x, pixel.y / frame_size.y)
	var x := lerpf(-table_width * 0.48, table_width * 0.48, normalized.x)
	var y := lerpf(2.15, 0.82, normalized.y)
	return Vector3(clampf(x, -table_width * 0.52, table_width * 0.52), clampf(y, 0.78, 2.2), racket_z)
