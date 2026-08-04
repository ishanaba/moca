#include "moca/hand_tracking/hand_geometry.hpp"

#include <algorithm>
#include <array>
#include <cmath>

namespace moca {
namespace {
float distance(const Keypoint& left, const Keypoint& right) {
  return std::hypot(left.x - right.x, left.y - right.y);
}
}  // namespace

Keypoint palm_center(std::span<const Keypoint> landmarks) {
  if (landmarks.size() < 18) return {};
  constexpr std::array<std::size_t, 5> palm_points{0, 5, 9, 13, 17};
  Keypoint center{};
  center.confidence = 1.0F;
  for (const auto index : palm_points) {
    center.x += landmarks[index].x;
    center.y += landmarks[index].y;
    center.confidence = std::min(center.confidence, landmarks[index].confidence);
  }
  center.x /= static_cast<float>(palm_points.size());
  center.y /= static_cast<float>(palm_points.size());
  return center;
}

bool is_gripping(std::span<const Keypoint> landmarks) {
  if (landmarks.size() < 21) return false;
  const auto center = palm_center(landmarks);
  const float palm_length = distance(landmarks[0], landmarks[9]);
  if (palm_length < 0.01F) return false;
  constexpr std::array<std::size_t, 4> fingertips{8, 12, 16, 20};
  int curled = 0;
  for (const auto index : fingertips) {
    if (distance(landmarks[index], center) < palm_length * 1.35F) ++curled;
  }
  return curled >= 3;
}

}  // namespace moca
