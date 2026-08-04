#pragma once

#include "moca/core/latest_value.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace moca::godot {

struct BladeSnapshot {
  std::uint32_t id;
  std::uint32_t person_id;
  std::string side;
  float x;
  float y;
  float confidence;
  bool gripping;
  std::vector<std::pair<float, float>> landmarks;
};

struct TrackingSnapshot {
  std::uint64_t capture_time_us;
  std::string source;
  std::vector<BladeSnapshot> players;
};

struct VideoSnapshot {
  std::uint64_t capture_time_us;
  std::vector<std::uint8_t> jpeg;
};

class TrackingBridge {
 public:
  // Accepts a serialized protocol v2 Envelope. Complete tracking frames replace
  // the previous value; malformed and non-frame envelopes leave it untouched.
  bool ingest(std::span<const std::byte> payload);
  [[nodiscard]] auto newer_than(std::uint64_t sequence) const {
    return latest_.newer_than(sequence);
  }
  [[nodiscard]] auto video_newer_than(std::uint64_t sequence) const {
    return latest_video_.newer_than(sequence);
  }

 private:
  LatestValue<TrackingSnapshot> latest_;
  LatestValue<VideoSnapshot> latest_video_;
};

}  // namespace moca::godot
