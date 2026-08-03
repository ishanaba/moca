extends SceneTree

const TrackingServiceScript = preload("res://scripts/tracking_service.gd")

var received := false
var tracking_service


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	tracking_service = TrackingServiceScript.new()
	root.add_child(tracking_service)
	tracking_service.snapshot_updated.connect(_on_snapshot)
	var error: Error = tracking_service.start_live("ws://127.0.0.1:8765")
	if error != OK:
		push_error("could not start live source: %s" % error_string(error))
		quit(1)
		return
	await create_timer(5.0).timeout
	if not received:
		push_error("no tracking snapshot received within timeout")
		quit(1)


func _on_snapshot(players: Array) -> void:
	if players.size() != 2:
		return
	if players[0].blade.x <= 0.0 or players[0].blade.y <= 0.0:
		return
	received = true
	print("Live transport smoke passed: ", players)
	quit(0)
