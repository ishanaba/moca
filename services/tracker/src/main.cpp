#include "moca/capture/gstreamer_capture.hpp"
#include "moca/hand_tracking/mediapipe_hand_tracker.hpp"
#include "moca/hand_tracking/wrist_hand_tracker.hpp"
#include "moca/inference/openvino_yolo_pose.hpp"
#include "moca/tracking/identity_tracker.hpp"
#include "moca/transport/websocket_server.hpp"

#include "tracking.pb.h"

#include <opencv2/core.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <chrono>
#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <span>
#include <string>
#include <thread>

namespace {
void draw_preview(const moca::CapturedFrame& captured,
                  const std::vector<moca::TrackedDetection>& tracked,
                  const std::vector<moca::HandObservation>& hands, double fps) {
  cv::Mat rgb(captured.height, captured.width, CV_8UC3,
              const_cast<std::uint8_t*>(captured.pixels.data()), captured.stride);
  cv::Mat image;
  cv::cvtColor(rgb, image, cv::COLOR_RGB2BGR);
  constexpr std::array<std::pair<int, int>, 16> skeleton{{
      {0, 1}, {0, 2}, {1, 3}, {2, 4}, {5, 6}, {5, 7}, {7, 9}, {6, 8},
      {8, 10}, {5, 11}, {6, 12}, {11, 12}, {11, 13}, {13, 15}, {12, 14}, {14, 16},
  }};
  for (const auto& person : tracked) {
    const auto& detection = person.detection;
    const cv::Scalar color = person.id % 2 == 0 ? cv::Scalar(255, 215, 70) : cv::Scalar(220, 80, 255);
    const cv::Point top_left(static_cast<int>(detection.box[0] * captured.width),
                             static_cast<int>(detection.box[1] * captured.height));
    const cv::Point bottom_right(static_cast<int>(detection.box[2] * captured.width),
                                 static_cast<int>(detection.box[3] * captured.height));
    cv::rectangle(image, top_left, bottom_right, color, 3);
    cv::putText(image,
                "Player " + std::to_string(person.id + 1) + "  " +
                    std::to_string(static_cast<int>(detection.confidence * 100)) + "%",
                {top_left.x, std::max(24, top_left.y - 8)}, cv::FONT_HERSHEY_SIMPLEX, 0.7, color,
                2, cv::LINE_AA);
    auto point = [&](int index) {
      const auto& keypoint = detection.keypoints[static_cast<std::size_t>(index)];
      return cv::Point(static_cast<int>(keypoint.x * captured.width),
                       static_cast<int>(keypoint.y * captured.height));
    };
    for (const auto& [from, to] : skeleton) {
      if (detection.keypoints[from].confidence > 0.35F &&
          detection.keypoints[to].confidence > 0.35F) {
        cv::line(image, point(from), point(to), color, 2, cv::LINE_AA);
      }
    }
    for (std::size_t index = 0; index < detection.keypoints.size(); ++index) {
      if (detection.keypoints[index].confidence <= 0.35F) continue;
      const bool wrist = index == 9 || index == 10;
      cv::circle(image, point(static_cast<int>(index)), wrist ? 10 : 4,
                 wrist ? cv::Scalar(40, 255, 40) : color, cv::FILLED, cv::LINE_AA);
    }
  }
  for (const auto& hand : hands) {
    const cv::Point center(static_cast<int>(hand.center.x * captured.width),
                           static_cast<int>(hand.center.y * captured.height));
    cv::circle(image, center, 14, cv::Scalar(30, 220, 255), 3, cv::LINE_AA);
    cv::putText(image, "Hand P" + std::to_string(hand.person_id), center + cv::Point(18, -12),
                cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(30, 220, 255), 2, cv::LINE_AA);
  }
  cv::rectangle(image, {0, 0}, {captured.width, 44}, cv::Scalar(15, 15, 15), cv::FILLED);
  cv::putText(image,
              "Moca live  |  persons: " + std::to_string(tracked.size()) + "  |  " +
                  std::to_string(static_cast<int>(std::round(fps))) + " FPS  |  Q/Esc: quit",
              {16, 30}, cv::FONT_HERSHEY_SIMPLEX, 0.72, cv::Scalar(255, 255, 255), 2,
              cv::LINE_AA);
  cv::imshow("Moca Camera + Pose", image);
}

std::string replay_payload(std::uint64_t frame_index) {
  moca::protocol::v2::Envelope envelope;
  auto* frame = envelope.mutable_tracking_frame();
  frame->set_version(2);
  frame->set_capture_time_us(frame_index * 33333);
  frame->set_inference_end_time_us(frame->capture_time_us() + 5000);
  frame->set_source("replay@CPU");
  frame->mutable_frame()->set_width(1280);
  frame->mutable_frame()->set_height(720);
  for (std::uint32_t player = 0; player < 2; ++player) {
    auto* person = frame->add_persons();
    person->set_id(player + 1);
    person->set_confidence(1.0F);
    for (int index = 0; index < 17; ++index) person->add_keypoints();
    const float phase = static_cast<float>(frame_index) * 0.08F + player * 3.1415926F;
    auto* wrist = person->mutable_keypoints(9);
    wrist->set_x((player == 0 ? 0.25F : 0.75F) + std::sin(phase) * 0.15F);
    wrist->set_y(0.5F + std::cos(phase * 1.3F) * 0.25F);
    wrist->set_confidence(1.0F);
  }
  return envelope.SerializeAsString();
}

std::string tracking_payload(const std::vector<moca::TrackedDetection>& tracked,
                             const std::vector<moca::HandObservation>& hands,
                             const moca::CapturedFrame& captured, const std::string& source,
                             const std::string& hand_source) {
  const auto capture_us = std::chrono::duration_cast<std::chrono::microseconds>(
                              captured.captured_at.time_since_epoch())
                              .count();
  const auto infer_us = std::chrono::duration_cast<std::chrono::microseconds>(
                            std::chrono::steady_clock::now().time_since_epoch())
                            .count();
  moca::protocol::v2::Envelope envelope;
  auto* frame = envelope.mutable_tracking_frame();
  frame->set_version(2);
  frame->set_capture_time_us(static_cast<std::uint64_t>(capture_us));
  frame->set_inference_end_time_us(static_cast<std::uint64_t>(infer_us));
  frame->set_source(source);
  frame->mutable_frame()->set_width(static_cast<std::uint32_t>(captured.width));
  frame->mutable_frame()->set_height(static_cast<std::uint32_t>(captured.height));
  for (const auto& tracked_person : tracked) {
    auto* person = frame->add_persons();
    person->set_id(tracked_person.id + 1);
    person->set_confidence(tracked_person.detection.confidence);
    for (const auto& point : tracked_person.detection.keypoints) {
      auto* keypoint = person->add_keypoints();
      keypoint->set_x(point.x);
      keypoint->set_y(point.y);
      keypoint->set_confidence(point.confidence);
    }
  }
  for (const auto& observation : hands) {
    auto* hand = frame->add_hands();
    hand->set_id(observation.id);
    if (observation.person_id != 0) hand->set_person_id(observation.person_id);
    hand->set_confidence(observation.confidence);
    hand->set_source(hand_source);
    hand->set_gripping(observation.gripping);
    hand->mutable_center()->set_x(observation.center.x);
    hand->mutable_center()->set_y(observation.center.y);
    hand->mutable_center()->set_confidence(observation.center.confidence);
    for (const auto& point : observation.landmarks) {
      auto* landmark = hand->add_landmarks();
      landmark->set_x(point.x);
      landmark->set_y(point.y);
      landmark->set_confidence(point.confidence);
    }
  }
  return envelope.SerializeAsString();
}

std::string camera_payload(const moca::CapturedFrame& captured) {
  cv::Mat rgb(captured.height, captured.width, CV_8UC3,
              const_cast<std::uint8_t*>(captured.pixels.data()), captured.stride);
  cv::Mat bgr;
  cv::cvtColor(rgb, bgr, cv::COLOR_RGB2BGR);
  std::vector<std::uint8_t> jpeg;
  cv::imencode(".jpg", bgr, jpeg, {cv::IMWRITE_JPEG_QUALITY, 70});
  const auto capture_us = std::chrono::duration_cast<std::chrono::microseconds>(
                              captured.captured_at.time_since_epoch())
                              .count();
  moca::protocol::v2::Envelope envelope;
  auto* video = envelope.mutable_camera_frame();
  video->set_capture_time_us(static_cast<std::uint64_t>(capture_us));
  video->set_width(static_cast<std::uint32_t>(captured.width));
  video->set_height(static_cast<std::uint32_t>(captured.height));
  video->set_jpeg_data(jpeg.data(), jpeg.size());
  return envelope.SerializeAsString();
}

int serve_replay(std::uint16_t port, int frame_limit) {
  moca::WebSocketServer server(port);
  std::string error;
  std::cout << "listening ws://127.0.0.1:" << port << '\n' << std::flush;
  if (!server.accept(error)) {
    std::cerr << "WebSocket accept failed: " << error << '\n';
    return 4;
  }
  for (int index = 0; frame_limit <= 0 || index < frame_limit; ++index) {
    const auto payload = replay_payload(static_cast<std::uint64_t>(index));
    const auto bytes = std::span(reinterpret_cast<const std::uint8_t*>(payload.data()), payload.size());
    if (!server.send(bytes, error)) {
      std::cerr << "WebSocket send stopped: " << error << '\n';
      return frame_limit <= 0 ? 0 : 5;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(33));
  }
  return 0;
}
}  // namespace

int main(int argc, char** argv) {
  std::string source = "replay";
  std::string device = "/dev/video0";
  std::string inference_device = "CPU";
  std::string model_path;
  int frame_limit = 0;
  int port = 8765;
  bool serve = false;
  bool preview = false;
  std::string hand_tracker_name = "wrist";
  std::string hand_model_path;
  std::string mediapipe_library_path;
  std::string mediapipe_delegate = "CPU";
  bool hand_only = false;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--source" && index + 1 < argc) source = argv[++index];
    if (argument == "--device" && index + 1 < argc) device = argv[++index];
    if (argument == "--inference-device" && index + 1 < argc) inference_device = argv[++index];
    if (argument == "--model" && index + 1 < argc) model_path = argv[++index];
    if (argument == "--frames" && index + 1 < argc) frame_limit = std::atoi(argv[++index]);
    if (argument == "--port" && index + 1 < argc) port = std::atoi(argv[++index]);
    if (argument == "--serve") serve = true;
    if (argument == "--preview") preview = true;
    if (argument == "--hand-tracker" && index + 1 < argc) hand_tracker_name = argv[++index];
    if (argument == "--hand-model" && index + 1 < argc) hand_model_path = argv[++index];
    if (argument == "--mediapipe-library" && index + 1 < argc) mediapipe_library_path = argv[++index];
    if (argument == "--mediapipe-delegate" && index + 1 < argc) mediapipe_delegate = argv[++index];
    if (argument == "--hand-only") hand_only = true;
  }

  std::cout << "moca-tracker 0.1.0 source=" << source << " protocol=2\n";
  if (source == "replay") return serve ? serve_replay(static_cast<std::uint16_t>(port), frame_limit) : 0;
  if (source != "camera") return 1;

  std::unique_ptr<moca::OpenVinoYoloPose> backend;
  if (!model_path.empty()) {
    try {
      backend = std::make_unique<moca::OpenVinoYoloPose>(model_path, inference_device);
      std::cout << "loaded model=" << backend->name() << " device=" << backend->device() << '\n';
    } catch (const std::exception& exception) {
      std::cerr << "model load failed: " << exception.what() << '\n';
      return 6;
    }
  } else if (serve && !hand_only) {
    std::cerr << "camera serving requires --model <path-to-model.xml>\n";
    return 7;
  }

  std::unique_ptr<moca::WebSocketServer> server;
  if (serve) {
    server = std::make_unique<moca::WebSocketServer>(static_cast<std::uint16_t>(port));
    std::cout << "listening ws://127.0.0.1:" << port << '\n' << std::flush;
    std::string server_error;
    if (!server->accept(server_error)) {
      std::cerr << "WebSocket accept failed: " << server_error << '\n';
      return 4;
    }
  }

  moca::GStreamerCapture capture(moca::GStreamerCapture::camera_pipeline(device));
  std::string error;
  if (!capture.start(error)) {
    std::cerr << "capture start failed: " << error << '\n';
    return 2;
  }
  moca::IdentityTracker identity;
  std::unique_ptr<moca::HandTracker> hand_tracker;
  if (hand_tracker_name == "wrist") {
    hand_tracker = std::make_unique<moca::WristHandTracker>();
  } else if (hand_tracker_name == "mediapipe") {
    if (hand_model_path.empty() || mediapipe_library_path.empty()) {
      std::cerr << "mediapipe hand tracking requires --hand-model and --mediapipe-library\n";
      return 9;
    }
    try {
      hand_tracker = std::make_unique<moca::MediaPipeHandTracker>(
          hand_model_path, mediapipe_library_path, mediapipe_delegate, 2, 0.35F, !hand_only);
    } catch (const std::exception& exception) {
      std::cerr << "hand tracker load failed: " << exception.what() << '\n';
      return 9;
    }
  } else if (hand_tracker_name != "none") {
    std::cerr << "unknown hand tracker: " << hand_tracker_name
              << " (expected wrist, mediapipe, or none)\n";
    return 9;
  }
  std::cout << "hand tracker=" << (hand_tracker ? hand_tracker->name() : "none") << '\n';
  int captured = 0;
  auto previous_frame_time = std::chrono::steady_clock::now();
  double smoothed_fps = 0.0;
  while (frame_limit <= 0 || captured < frame_limit) {
    auto frame = capture.pull(std::chrono::seconds(2), error);
    if (!frame) {
      std::cerr << "capture failed: " << error << '\n';
      return 3;
    }
    ++captured;
    std::vector<moca::TrackedDetection> tracked;
    std::vector<moca::HandObservation> hands;
    try {
      const moca::ImageView view{frame->bytes(), frame->width, frame->height, frame->stride};
      if (backend) {
        tracked = identity.update(backend->infer(view), frame->captured_at);
      }
      if (hand_tracker) hands = hand_tracker->infer(view, tracked);
    } catch (const std::exception& exception) {
      std::cerr << "inference failed: " << exception.what() << '\n';
      return 8;
    }
    if (server) {
      const auto payload = tracking_payload(tracked, hands, *frame,
                                            backend ? backend->name() + "@" + backend->device()
                                                    : "mediapipe-only",
                                            hand_tracker ? hand_tracker->name() : "none");
      const auto bytes =
          std::span(reinterpret_cast<const std::uint8_t*>(payload.data()), payload.size());
      if (!server->send(bytes, error)) {
        std::cerr << "WebSocket send stopped: " << error << '\n';
        return frame_limit <= 0 ? 0 : 5;
      }
      if (captured % 2 == 0) {
        const auto video = camera_payload(*frame);
        const auto video_bytes =
            std::span(reinterpret_cast<const std::uint8_t*>(video.data()), video.size());
        if (!server->send(video_bytes, error)) {
          std::cerr << "camera stream stopped: " << error << '\n';
          return frame_limit <= 0 ? 0 : 5;
        }
      }
    }
    const auto preview_time = std::chrono::steady_clock::now();
    const double frame_seconds = std::chrono::duration<double>(preview_time - previous_frame_time).count();
    previous_frame_time = preview_time;
    if (frame_seconds > 0.0) {
      const double instantaneous_fps = 1.0 / frame_seconds;
      smoothed_fps = smoothed_fps == 0.0 ? instantaneous_fps
                                         : smoothed_fps * 0.9 + instantaneous_fps * 0.1;
    }
    if (preview) {
      draw_preview(*frame, tracked, hands, smoothed_fps);
      const int key = cv::waitKey(1);
      if (key == 27 || key == 'q' || key == 'Q') break;
    }
    if (captured == 1 || captured % 30 == 0) {
      std::cout << "captured frame=" << captured << " size=" << frame->width << 'x'
                << frame->height << " bytes=" << frame->pixels.size()
                << " persons=" << tracked.size() << '\n';
    }
  }
}
