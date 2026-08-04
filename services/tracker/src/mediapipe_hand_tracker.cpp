#include "moca/hand_tracking/mediapipe_hand_tracker.hpp"

#include "mediapipe_c_api.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <dlfcn.h>
#include <stdexcept>
#include <utility>
#include <vector>

namespace moca {
namespace mp = mediapipe_c;

namespace {
template <typename Function>
Function load_symbol(void* library, const char* name) {
  dlerror();
  auto* symbol = dlsym(library, name);
  if (const char* error = dlerror()) throw std::runtime_error(std::string(name) + ": " + error);
  return reinterpret_cast<Function>(symbol);
}

std::string take_error(char* error) {
  if (!error) return "unknown MediaPipe error";
  std::string message(error);
  std::free(error);
  return message;
}
}  // namespace

struct MediaPipeHandTracker::State {
  using Create = mp::MpStatus (*)(mp::HandLandmarkerOptions*, mp::MpHandLandmarkerPtr*, char**);
  using Detect = mp::MpStatus (*)(mp::MpHandLandmarkerPtr, mp::MpImagePtr, const void*,
                                  mp::HandLandmarkerResult*, char**);
  using CloseResult = void (*)(mp::HandLandmarkerResult*);
  using Close = mp::MpStatus (*)(mp::MpHandLandmarkerPtr, char**);
  using CreateImage = mp::MpStatus (*)(mp::MpImageFormat, int, int, const std::uint8_t*, int,
                                       mp::MpImagePtr*, char**);
  using FreeImage = void (*)(mp::MpImagePtr);

  State(const std::string& model, const std::string& library_path, int max_hands, float confidence) {
    library = dlopen(library_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!library) throw std::runtime_error("cannot load MediaPipe runtime " + library_path + ": " + dlerror());
    try {
      create = load_symbol<Create>(library, "MpHandLandmarkerCreate");
      detect = load_symbol<Detect>(library, "MpHandLandmarkerDetectImage");
      close_result = load_symbol<CloseResult>(library, "MpHandLandmarkerCloseResult");
      close = load_symbol<Close>(library, "MpHandLandmarkerClose");
      create_image = load_symbol<CreateImage>(library, "MpImageCreateFromUint8Data");
      free_image = load_symbol<FreeImage>(library, "MpImageFree");

      mp::HandLandmarkerOptions options{};
      options.base_options.model_asset_path = model.c_str();
      options.base_options.host_system = mp::HOST_SYSTEM_LINUX;
      options.running_mode = mp::IMAGE;
      options.num_hands = max_hands;
      options.min_hand_detection_confidence = confidence;
      options.min_hand_presence_confidence = confidence;
      options.min_tracking_confidence = confidence;
      char* error = nullptr;
      if (create(&options, &landmarker, &error) != mp::kMpOk)
        throw std::runtime_error("MediaPipe Hand Landmarker initialization failed: " + take_error(error));
    } catch (...) {
      dlclose(library);
      library = nullptr;
      throw;
    }
  }

  ~State() {
    if (landmarker && close) {
      char* error = nullptr;
      close(landmarker, &error);
      std::free(error);
    }
    if (library) dlclose(library);
  }

  void* library = nullptr;
  mp::MpHandLandmarkerPtr landmarker = nullptr;
  Create create = nullptr;
  Detect detect = nullptr;
  CloseResult close_result = nullptr;
  Close close = nullptr;
  CreateImage create_image = nullptr;
  FreeImage free_image = nullptr;
};

MediaPipeHandTracker::MediaPipeHandTracker(std::string model_path, std::string library_path,
                                           int max_hands, float confidence)
    : state_(std::make_unique<State>(model_path, library_path, max_hands, confidence)) {}
MediaPipeHandTracker::~MediaPipeHandTracker() = default;
std::string MediaPipeHandTracker::name() const { return "mediapipe-hand-landmarker"; }

std::vector<HandObservation> MediaPipeHandTracker::infer(
    ImageView image, std::span<const TrackedDetection> persons) {
  if (image.width <= 0 || image.height <= 0 || image.stride < image.width * 3 || image.bytes.empty()) return {};

  // GStreamer supplies BGR rows (potentially padded); MediaPipe accepts packed RGB.
  std::vector<std::uint8_t> rgb(static_cast<std::size_t>(image.width * image.height * 3));
  for (int y = 0; y < image.height; ++y) {
    const auto* source = image.bytes.data() + static_cast<std::size_t>(y * image.stride);
    auto* target = rgb.data() + static_cast<std::size_t>(y * image.width * 3);
    for (int x = 0; x < image.width; ++x) {
      target[x * 3] = source[x * 3 + 2];
      target[x * 3 + 1] = source[x * 3 + 1];
      target[x * 3 + 2] = source[x * 3];
    }
  }

  mp::MpImagePtr mp_image = nullptr;
  char* error = nullptr;
  if (state_->create_image(mp::kMpImageFormatSrgb, image.width, image.height, rgb.data(),
                           static_cast<int>(rgb.size()), &mp_image, &error) != mp::kMpOk)
    throw std::runtime_error("MediaPipe image creation failed: " + take_error(error));

  mp::HandLandmarkerResult result{};
  error = nullptr;
  const auto status = state_->detect(state_->landmarker, mp_image, nullptr, &result, &error);
  state_->free_image(mp_image);
  if (status != mp::kMpOk) throw std::runtime_error("MediaPipe hand detection failed: " + take_error(error));

  std::vector<HandObservation> hands;
  hands.reserve(result.hand_landmarks_count);
  for (std::uint32_t index = 0; index < result.hand_landmarks_count; ++index) {
    const auto& source = result.hand_landmarks[index];
    if (!source.landmarks || source.landmarks_count == 0) continue;
    std::vector<Keypoint> landmarks;
    landmarks.reserve(source.landmarks_count);
    for (std::uint32_t point = 0; point < source.landmarks_count; ++point) {
      const auto& landmark = source.landmarks[point];
      landmarks.push_back({std::clamp(landmark.x, 0.0F, 1.0F),
                           std::clamp(landmark.y, 0.0F, 1.0F),
                           landmark.has_presence ? landmark.presence : 1.0F});
    }
    const Keypoint center = landmarks.front();  // landmark 0 is the wrist.
    float confidence = 1.0F;
    if (index < result.handedness_count && result.handedness[index].categories_count > 0)
      confidence = result.handedness[index].categories[0].score;

    std::uint32_t person_id = 0;
    std::uint32_t hand_id = 1000 + index;
    float best_distance = 0.18F * 0.18F;
    bool matched_right = false;
    for (const auto& person : persons) {
      for (int wrist_index : {9, 10}) {
        const auto& wrist = person.detection.keypoints[wrist_index];
        if (wrist.confidence < 0.15F) continue;
        const float dx = center.x - wrist.x;
        const float dy = center.y - wrist.y;
        const float distance = dx * dx + dy * dy;
        if (distance < best_distance) {
          best_distance = distance;
          person_id = person.id + 1;
          matched_right = wrist_index == 10;
          hand_id = person.id * 2 + (matched_right ? 2 : 1);
        }
      }
    }
    hands.push_back({hand_id, person_id, center, std::move(landmarks), confidence});
  }
  state_->close_result(&result);
  return hands;
}

}  // namespace moca
