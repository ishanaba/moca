#pragma once
#include "moca/inference/backend.hpp"
#include <chrono>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace moca {
struct TrackedDetection { std::uint32_t id; Detection detection; };
class IdentityTracker {
 public:
  explicit IdentityTracker(std::chrono::milliseconds hold = std::chrono::seconds(1));
  std::vector<TrackedDetection> update(std::vector<Detection> detections, std::chrono::steady_clock::time_point now);
  [[nodiscard]] std::size_t active_tracks() const { return tracks_.size(); }
 private:
  struct Track { std::array<float,4> box; std::chrono::steady_clock::time_point seen; };
  std::chrono::milliseconds hold_; std::uint32_t next_id_{0}; std::unordered_map<std::uint32_t,Track> tracks_;
};
}
