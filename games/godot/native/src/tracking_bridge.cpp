#include "moca/godot/tracking_bridge.hpp"

#include "tracking.pb.h"

#include <algorithm>
#include <limits>

namespace moca::godot {

bool TrackingBridge::ingest(std::span<const std::byte> payload) {
  if (payload.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) return false;

  protocol::v2::Envelope envelope;
  if (!envelope.ParseFromArray(payload.data(), static_cast<int>(payload.size()))) {
    return false;
  }

  if (envelope.has_camera_frame()) {
    const auto& frame = envelope.camera_frame();
    if (frame.jpeg_data().empty() || frame.width() == 0 || frame.height() == 0) return false;
    VideoSnapshot snapshot{frame.capture_time_us(), {}};
    snapshot.jpeg.assign(frame.jpeg_data().begin(), frame.jpeg_data().end());
    latest_video_.replace(std::move(snapshot));
    return true;
  }
  if (!envelope.has_tracking_frame()) return false;

  const auto& frame = envelope.tracking_frame();
  if (frame.version() != 2 || !frame.has_frame() || frame.frame().width() == 0 ||
      frame.frame().height() == 0) {
    return false;
  }

  TrackingSnapshot snapshot{frame.capture_time_us(), frame.source(), {}};
  snapshot.players.reserve(static_cast<std::size_t>(frame.persons_size()));
  for (const auto& person : frame.persons()) {
    bool has_explicit_hand = false;
    for (const auto& hand : frame.hands()) {
      if (!hand.has_person_id() || hand.person_id() != person.id() || !hand.has_center()) continue;
      has_explicit_hand = true;
      snapshot.players.push_back({hand.id(), std::clamp(hand.center().x(), 0.0F, 1.0F),
                                  std::clamp(hand.center().y(), 0.0F, 1.0F),
                                  hand.confidence(), hand.gripping()});
    }
    if (has_explicit_hand) continue;
    // COCO-17 wrists are 9/10 and elbows are 7/8. Prefer the stronger arm and
    // retain the legacy estimate for older producers without explicit hands.
    if (person.keypoints_size() <= 10) continue;
    const auto& left = person.keypoints(9);
    const auto& right = person.keypoints(10);
    const bool use_right = right.confidence() > left.confidence();
    const auto& wrist = use_right ? right : left;
    const auto& elbow = person.keypoints(use_right ? 8 : 7);
    float hand_x = wrist.x();
    float hand_y = wrist.y();
    if (elbow.confidence() > 0.25F) {
      constexpr float extension = 0.18F;
      hand_x += (wrist.x() - elbow.x()) * extension;
      hand_y += (wrist.y() - elbow.y()) * extension;
    }
    snapshot.players.push_back({person.id(), std::clamp(hand_x, 0.0F, 1.0F),
                                std::clamp(hand_y, 0.0F, 1.0F),
                                wrist.confidence() * person.confidence(), false});
  }
  // Full-frame hand detectors can publish before a body/person is visible.
  // Expose every unassociated hand directly as a playable input.
  for (const auto& hand : frame.hands()) {
    if (hand.has_person_id() || !hand.has_center()) continue;
    snapshot.players.push_back(
        {hand.id(), std::clamp(hand.center().x(), 0.0F, 1.0F),
         std::clamp(hand.center().y(), 0.0F, 1.0F), hand.confidence(), hand.gripping()});
  }
  latest_.replace(std::move(snapshot));
  return true;
}

}  // namespace moca::godot
