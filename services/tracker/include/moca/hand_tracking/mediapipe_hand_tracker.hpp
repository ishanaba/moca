#pragma once

#include "moca/hand_tracking/backend.hpp"

#include <memory>
#include <string>

namespace moca {

// Google MediaPipe Hand Landmarker backend. The MediaPipe C runtime is loaded
// dynamically so the existing wrist backend and normal builds have no new
// link-time dependency.
class MediaPipeHandTracker final : public HandTracker {
 public:
  MediaPipeHandTracker(std::string model_path, std::string library_path,
                       int max_hands = 4, float confidence = 0.35F);
  ~MediaPipeHandTracker() override;
  MediaPipeHandTracker(const MediaPipeHandTracker&) = delete;
  MediaPipeHandTracker& operator=(const MediaPipeHandTracker&) = delete;

  [[nodiscard]] std::string name() const override;
  std::vector<HandObservation> infer(
      ImageView image, std::span<const TrackedDetection> persons) override;

 private:
  struct State;
  std::unique_ptr<State> state_;
};

}  // namespace moca
