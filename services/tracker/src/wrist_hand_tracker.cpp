#include "moca/hand_tracking/wrist_hand_tracker.hpp"

#include <algorithm>

namespace moca {

std::string WristHandTracker::name() const { return "wrist-estimate"; }

std::vector<HandObservation> WristHandTracker::infer(
    ImageView, std::span<const TrackedDetection> persons) {
  std::vector<HandObservation> hands;
  hands.reserve(persons.size());
  for (const auto& person : persons) {
    const auto& left = person.detection.keypoints[9];
    const auto& right = person.detection.keypoints[10];
    auto add_hand = [&](const Keypoint& wrist, const Keypoint& elbow, bool is_right) {
      if (wrist.confidence < 0.15F) return;
      Keypoint center = wrist;
      if (elbow.confidence > 0.25F) {
        constexpr float extension = 0.18F;
        center.x += (wrist.x - elbow.x) * extension;
        center.y += (wrist.y - elbow.y) * extension;
      }
      center.x = std::clamp(center.x, 0.0F, 1.0F);
      center.y = std::clamp(center.y, 0.0F, 1.0F);
      center.confidence = wrist.confidence * person.detection.confidence;
      const std::uint32_t person_id = person.id + 1;
      const std::uint32_t hand_id = person.id * 2 + (is_right ? 2 : 1);
      hands.push_back({hand_id, person_id, center, {}, center.confidence, false});
    };
    add_hand(left, person.detection.keypoints[7], false);
    add_hand(right, person.detection.keypoints[8], true);
  }
  return hands;
}

}  // namespace moca
