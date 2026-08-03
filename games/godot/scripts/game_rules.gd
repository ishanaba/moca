class_name GameRules
extends RefCounted

const FRUIT_SCORE := 100
const BOMB_PENALTY := 250
const MAX_SCORE := 1000


static func segment_hits_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> bool:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return start.distance_squared_to(center) <= radius * radius
	var amount: float = clamp((center - start).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start + segment * amount
	return closest.distance_squared_to(center) <= radius * radius


static func score_for_target(is_bomb: bool) -> int:
	return -BOMB_PENALTY if is_bomb else FRUIT_SCORE


static func clamp_score(score: int) -> int:
	return clampi(score, 0, MAX_SCORE)
