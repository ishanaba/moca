#pragma once

#include "moca/inference/backend.hpp"
#include "moca/tracking/identity_tracker.hpp"

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace moca {

struct HandObservation {
  std::uint32_t id;
  // Zero means the hand has not been associated with a body/person track.
  // A full-frame palm detector can therefore report a hand immediately.
  std::uint32_t person_id;
  Keypoint center;
  std::vector<Keypoint> landmarks;
  float confidence;
};

// A hand backend consumes the camera image plus stable, person-associated body
// detections. Implementations may discover hands from the image independently,
// then optionally use body wrists to associate them with a person.
class HandTracker {
 public:
  virtual ~HandTracker() = default;
  [[nodiscard]] virtual std::string name() const = 0;
  virtual std::vector<HandObservation> infer(
      ImageView image, std::span<const TrackedDetection> persons) = 0;
};

}  // namespace moca
