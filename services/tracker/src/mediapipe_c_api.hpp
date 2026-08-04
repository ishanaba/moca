#pragma once

// Minimal ABI declarations for the Apache-2.0 MediaPipe Tasks C API v0.10.35.
// Keeping these private lets moca compile without MediaPipe headers; the
// official libmediapipe.so is loaded at runtime.
#include <cstdint>

namespace moca::mediapipe_c {

enum MpStatus { kMpOk = 0 };
enum Delegate { CPU = 0, GPU = 1, EDGETPU_NNAPI = 2 };
enum HostEnvironment { HOST_ENVIRONMENT_UNKNOWN = 0 };
enum HostSystem { HOST_SYSTEM_UNKNOWN = 0, HOST_SYSTEM_LINUX = 1 };
enum RunningMode { IMAGE = 1, VIDEO = 2, LIVE_STREAM = 3 };
enum MpImageFormat { kMpImageFormatUnknown = 0, kMpImageFormatSrgb = 1 };

struct BaseOptions {
  const char* model_asset_buffer;
  unsigned int model_asset_buffer_count;
  const char* model_asset_path;
  Delegate delegate;
  HostEnvironment host_environment;
  HostSystem host_system;
  const char* host_version;
  const char* ca_bundle_path;
};
struct Category { int index; float score; char* category_name; char* display_name; };
struct Categories { Category* categories; std::uint32_t categories_count; };
struct NormalizedLandmark {
  float x, y, z;
  bool has_visibility;
  float visibility;
  bool has_presence;
  float presence;
  char* name;
};
struct NormalizedLandmarks {
  NormalizedLandmark* landmarks;
  std::uint32_t landmarks_count;
};
struct Landmark {
  float x, y, z;
  bool has_visibility;
  float visibility;
  bool has_presence;
  float presence;
  char* name;
};
struct Landmarks { Landmark* landmarks; std::uint32_t landmarks_count; };
struct HandLandmarkerResult {
  Categories* handedness;
  std::uint32_t handedness_count;
  NormalizedLandmarks* hand_landmarks;
  std::uint32_t hand_landmarks_count;
  Landmarks* hand_world_landmarks;
  std::uint32_t hand_world_landmarks_count;
};
using MpHandLandmarkerPtr = struct MpHandLandmarkerInternal*;
using MpImagePtr = struct MpImageInternal*;
struct HandLandmarkerOptions {
  BaseOptions base_options{};
  RunningMode running_mode = IMAGE;
  int num_hands = 1;
  float min_hand_detection_confidence = 0.5F;
  float min_hand_presence_confidence = 0.5F;
  float min_tracking_confidence = 0.5F;
  void (*result_callback)(MpStatus, const HandLandmarkerResult*, MpImagePtr, std::int64_t) = nullptr;
};

}  // namespace moca::mediapipe_c
