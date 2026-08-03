#include "moca/inference/openvino_yolo_pose.hpp"

#include <openvino/openvino.hpp>

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

namespace moca {
namespace {
constexpr int kInputSize = 640;
float clamp_unit(float value) { return std::clamp(value, 0.0F, 1.0F); }
}  // namespace

struct OpenVinoYoloPose::State {
  State(const std::string& model_path, std::string requested_device, float threshold)
      : device(std::move(requested_device)), confidence_threshold(threshold) {
    const auto model = core.read_model(model_path);
    compiled = core.compile_model(model, device, ov::hint::performance_mode(ov::hint::PerformanceMode::LATENCY));
    request = compiled.create_infer_request();
  }
  ov::Core core;
  ov::CompiledModel compiled;
  ov::InferRequest request;
  std::string device;
  float confidence_threshold;
};

OpenVinoYoloPose::OpenVinoYoloPose(const std::string& model_path, std::string device,
                                   float confidence_threshold)
    : state_(std::make_unique<State>(model_path, std::move(device), confidence_threshold)) {}
OpenVinoYoloPose::~OpenVinoYoloPose() = default;
std::string OpenVinoYoloPose::name() const { return "yolo26n-pose"; }
std::string OpenVinoYoloPose::device() const { return state_->device; }

std::vector<Detection> OpenVinoYoloPose::infer(ImageView image) {
  if (image.width <= 0 || image.height <= 0 || image.stride < image.width * 3 ||
      image.bytes.size() < static_cast<std::size_t>(image.stride * image.height)) {
    throw std::invalid_argument("invalid RGB image view");
  }
  ov::Tensor input(ov::element::f32, {1, 3, kInputSize, kInputSize});
  auto* values = input.data<float>();
  std::fill(values, values + input.get_size(), 114.0F / 255.0F);
  const float scale = std::min(static_cast<float>(kInputSize) / image.width,
                               static_cast<float>(kInputSize) / image.height);
  const int resized_width = std::max(1, static_cast<int>(std::round(image.width * scale)));
  const int resized_height = std::max(1, static_cast<int>(std::round(image.height * scale)));
  const int pad_x = (kInputSize - resized_width) / 2;
  const int pad_y = (kInputSize - resized_height) / 2;
  const std::size_t plane = kInputSize * kInputSize;
  for (int y = 0; y < resized_height; ++y) {
    const int source_y = std::min(image.height - 1, static_cast<int>(y / scale));
    for (int x = 0; x < resized_width; ++x) {
      const int source_x = std::min(image.width - 1, static_cast<int>(x / scale));
      const auto offset = static_cast<std::size_t>(source_y * image.stride + source_x * 3);
      const auto target = static_cast<std::size_t>((y + pad_y) * kInputSize + x + pad_x);
      values[target] = image.bytes[offset] / 255.0F;
      values[plane + target] = image.bytes[offset + 1] / 255.0F;
      values[plane * 2 + target] = image.bytes[offset + 2] / 255.0F;
    }
  }

  state_->request.set_input_tensor(input);
  state_->request.infer();
  const ov::Tensor output = state_->request.get_output_tensor();
  const auto shape = output.get_shape();
  if (shape.size() != 3 || shape[0] != 1 || shape[2] < 57) {
    throw std::runtime_error("unexpected YOLO pose output shape");
  }
  const auto* predictions = output.data<const float>();
  std::vector<Detection> detections;
  for (std::size_t row_index = 0; row_index < shape[1]; ++row_index) {
    const float* row = predictions + row_index * shape[2];
    if (row[4] < state_->confidence_threshold) continue;
    auto normalize_x = [&](float x) { return clamp_unit((x - pad_x) / scale / image.width); };
    auto normalize_y = [&](float y) { return clamp_unit((y - pad_y) / scale / image.height); };
    Detection detection{};
    detection.box = {normalize_x(row[0]), normalize_y(row[1]), normalize_x(row[2]),
                     normalize_y(row[3])};
    detection.confidence = row[4];
    for (std::size_t index = 0; index < detection.keypoints.size(); ++index) {
      const std::size_t offset = 6 + index * 3;
      detection.keypoints[index] =
          {normalize_x(row[offset]), normalize_y(row[offset + 1]), row[offset + 2]};
    }
    detections.push_back(detection);
  }
  return detections;
}

}  // namespace moca
