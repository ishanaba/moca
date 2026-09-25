GODOT ?= $(shell command -v godot 2>/dev/null || echo flatpak run org.godotengine.Godot)

.PHONY: configure build test tracker camera-smoke compose model-test godot godot-test live table-tennis-live magic-garden-live mediapipe-setup mediapipe-live 1 2 3
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
	$(GODOT) --path games/godot
godot-test:
	$(GODOT) --headless --path games/godot --script res://tests/run_tests.gd
live: build
	./scripts/run-live.sh
table-tennis-live: live
magic-garden-live: build
	./scripts/run-live.sh $(or $(filter 1 2 3,$(MAKECMDGOALS)),2)
# Allow the friendly `make magic-garden-live 1` syntax. These goals only carry
# the selected level to the recipe above.
1 2 3:
	@:
mediapipe-setup:
	./scripts/setup-mediapipe.sh
mediapipe-live: build
	./scripts/run-mediapipe-live.sh
