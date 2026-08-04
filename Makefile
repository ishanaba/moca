.PHONY: configure build test tracker camera-smoke compose model-test godot godot-test live table-tennis-live mediapipe-setup mediapipe-live
configure:
	cmake --preset dev
build:
	cmake --build --preset dev
test: build
	ctest --preset dev
tracker: build
	./build/dev/services/tracker/moca-tracker --source replay
camera-smoke:
	gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink
compose:
	docker compose -f deployments/compose/docker-compose.yml up --build
model-test:
	cd tools/models && python -m pytest
godot:
	godot --path games/godot
godot-test:
	godot --headless --path games/godot --script res://tests/run_tests.gd
live: build
	./scripts/run-live.sh
table-tennis-live: live
mediapipe-setup:
	./scripts/setup-mediapipe.sh
mediapipe-live: build
	./scripts/run-mediapipe-live.sh
