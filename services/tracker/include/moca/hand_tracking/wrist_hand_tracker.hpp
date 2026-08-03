#pragma once

#include "moca/hand_tracking/backend.hpp"


namespace moca {

// Lightweight fallback that estimates a hand center just beyond the strongest
// wrist. It also proves the same interface used by future MediaPipe/RTMPose
// implementations without adding a new runtime dependency.
class WristHandTracker final : public HandTracker {
 public:
  [[nodiscard]] std::string name() const override;
  std::vector<HandObservation> infer(
      ImageView image, std::span<const TrackedDetection> persons) override;

};

}  // namespace moca
