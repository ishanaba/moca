#pragma once

#include <chrono>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <vector>

namespace moca {

struct CapturedFrame {
  std::vector<std::uint8_t> pixels;
  int width{};
  int height{};
  int stride{};
  std::chrono::steady_clock::time_point captured_at;

  [[nodiscard]] std::span<const std::uint8_t> bytes() const { return pixels; }
};

class GStreamerCapture {
 public:
  explicit GStreamerCapture(std::string pipeline_description);
  ~GStreamerCapture();
  GStreamerCapture(const GStreamerCapture&) = delete;
  GStreamerCapture& operator=(const GStreamerCapture&) = delete;
  GStreamerCapture(GStreamerCapture&&) noexcept;
  GStreamerCapture& operator=(GStreamerCapture&&) noexcept;

  [[nodiscard]] bool start(std::string& error);
  void stop();
  [[nodiscard]] bool is_running() const;
  [[nodiscard]] std::unique_ptr<CapturedFrame> pull(std::chrono::milliseconds timeout,
                                                    std::string& error);

  [[nodiscard]] static std::string camera_pipeline(const std::string& device,
                                                   int width = 1280, int height = 720,
                                                   int fps = 30);

 private:
  struct State;
  std::unique_ptr<State> state_;
};

}  // namespace moca
