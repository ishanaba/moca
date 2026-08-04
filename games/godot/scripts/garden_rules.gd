class_name GardenRules
extends RefCounted

const INTRO_END := 15.0
const SEEDS_END := 65.0
const BUTTERFLIES_END := 115.0
const BUBBLES_END := 165.0
const SESSION_END := 180.0


static func stage_for_elapsed(elapsed: float) -> String:
	if elapsed < INTRO_END:
		return "welcome"
	if elapsed < SEEDS_END:
		return "seeds"
	if elapsed < BUTTERFLIES_END:
		return "butterflies"
	if elapsed < BUBBLES_END:
		return "bubbles"
	if elapsed < SESSION_END:
		return "celebration"
	return "complete"


static func segment_hits_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> bool:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return start.distance_squared_to(center) <= radius * radius
	var amount: float = clampf((center - start).dot(segment) / length_squared, 0.0, 1.0)
	return (start + segment * amount).distance_squared_to(center) <= radius * radius


static func closest_point_on_path(point: Vector2, path: Array) -> Vector2:
	if path.is_empty():
		return point
	var closest: Vector2 = path[0]
	var closest_distance := INF
	for index in path.size() - 1:
		var start: Vector2 = path[index]
		var finish: Vector2 = path[index + 1]
		var segment := finish - start
		var amount := 0.0
		if segment.length_squared() > 0.000001:
			amount = clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var candidate := start + segment * amount
		var distance := point.distance_squared_to(candidate)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	return closest


static func difficulty_for_history(history: Array) -> Dictionary:
	if history.is_empty():
		return {"radius": 90.0, "speed": 50.0, "lifetime": 7.0}
	var successes := 0
	for result in history:
		if bool(result):
			successes += 1
	var ratio := float(successes) / float(history.size())
	if ratio > 0.8:
		return {"radius": 70.0, "speed": 100.0, "lifetime": 5.5}
	if ratio < 0.45:
		return {"radius": 105.0, "speed": 35.0, "lifetime": 8.0}
	return {"radius": 85.0, "speed": 70.0, "lifetime": 6.5}


static func select_person(hands: Array) -> int:
	var confidence_by_person := {}
	for hand_value in hands:
		if not hand_value is Dictionary:
			continue
		var hand: Dictionary = hand_value
		var person_id := int(hand.get("person_id", hand.get("id", 0)))
		if person_id <= 0:
			continue
		confidence_by_person[person_id] = float(confidence_by_person.get(person_id, 0.0)) + float(hand.get("confidence", 0.0))
	var best_person := 0
	var best_confidence := -1.0
	for person_value in confidence_by_person:
		var person_id := int(person_value)
		var confidence := float(confidence_by_person[person_id])
		if confidence > best_confidence:
			best_confidence = confidence
			best_person = person_id
	return best_person


static func next_wave_state(previous_direction: int, switches: int, last_switch_ms: int, horizontal_speed: float, now_ms: int, required_switches := 3, speed_threshold := 360.0) -> Dictionary:
	var direction := 0
	if horizontal_speed > speed_threshold:
		direction = 1
	elif horizontal_speed < -speed_threshold:
		direction = -1
	if direction == 0 or direction == previous_direction:
		return {"direction": previous_direction, "switches": switches, "last_ms": last_switch_ms, "complete": false}
	var next_switches := switches
	if last_switch_ms < 0 or now_ms - last_switch_ms > 1400:
		next_switches = 1
	else:
		next_switches += 1
	var complete := next_switches >= required_switches
	return {"direction": direction, "switches": 0 if complete else next_switches, "last_ms": now_ms, "complete": complete}
