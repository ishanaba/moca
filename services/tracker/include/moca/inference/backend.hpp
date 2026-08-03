#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace moca {
struct Keypoint { float x; float y; float confidence; };
struct Detection { std::array<float,4> box; std::array<Keypoint,17> keypoints; float confidence; };
struct ImageView { std::span<const std::uint8_t> bytes; int width; int height; int stride; };
class PoseBackend {
 public:
  virtual ~PoseBackend() = default;
  [[nodiscard]] virtual std::string name() const = 0;
  [[nodiscard]] virtual std::string device() const = 0;
  virtual std::vector<Detection> infer(ImageView image) = 0;
};
}
