#include "moca/godot/tracking_bridge.hpp"

#include "tracking.pb.h"

#include <cassert>
#include <cstddef>
#include <string>

namespace {
std::span<const std::byte> bytes(const std::string& value) {
  return {reinterpret_cast<const std::byte*>(value.data()), value.size()};
}
}  // namespace

int main() {
  moca::godot::TrackingBridge bridge;
  assert(!bridge.ingest(bytes("not protobuf")));
  assert(!bridge.newer_than(0));

  moca::protocol::v2::Envelope heartbeat;
  heartbeat.mutable_heartbeat()->set_monotonic_time_us(12);
  assert(!bridge.ingest(bytes(heartbeat.SerializeAsString())));

  moca::protocol::v2::Envelope camera;
  camera.mutable_camera_frame()->set_capture_time_us(99);
  camera.mutable_camera_frame()->set_width(2);
  camera.mutable_camera_frame()->set_height(2);
  camera.mutable_camera_frame()->set_jpeg_data("jpeg");
  assert(bridge.ingest(bytes(camera.SerializeAsString())));
  const auto video = bridge.video_newer_than(0);
  assert(video && video->first == 1 && video->second.capture_time_us == 99);
  assert(video->second.jpeg.size() == 4);

  moca::protocol::v2::Envelope envelope;
  auto* frame = envelope.mutable_tracking_frame();
  frame->set_version(2);
  frame->set_capture_time_us(1234);
  frame->set_source("replay@test");
  frame->mutable_frame()->set_width(1280);
  frame->mutable_frame()->set_height(720);
  auto* person = frame->add_persons();
  person->set_id(7);
  person->set_confidence(0.8F);
  for (int index = 0; index < 17; ++index) person->add_keypoints();
  person->mutable_keypoints(9)->set_x(0.25F);
  person->mutable_keypoints(9)->set_y(0.5F);
  person->mutable_keypoints(9)->set_confidence(0.9F);
  person->mutable_keypoints(7)->set_x(0.25F);
  person->mutable_keypoints(7)->set_y(0.5F);
  person->mutable_keypoints(7)->set_confidence(0.8F);
  person->mutable_keypoints(10)->set_confidence(0.2F);

  assert(bridge.ingest(bytes(envelope.SerializeAsString())));
  const auto first = bridge.newer_than(0);
  assert(first && first->first == 1);
  assert(first->second.capture_time_us == 1234);
  assert(first->second.source == "replay@test");
  assert(first->second.players.size() == 1);
  assert(first->second.players[0].id == 7);
  assert(first->second.players[0].x == 0.25F);
  assert(first->second.players[0].y == 0.5F);
  assert(first->second.players[0].confidence > 0.71F);
  assert(first->second.players[0].confidence < 0.73F);
  assert(!bridge.newer_than(first->first));

  frame->set_capture_time_us(2345);
  auto* hand = frame->add_hands();
  hand->set_person_id(7);
  hand->set_confidence(0.95F);
  hand->set_source("test-hand");
  hand->set_gripping(true);
  hand->mutable_center()->set_x(0.6F);
  hand->mutable_center()->set_y(0.7F);
  hand->mutable_center()->set_confidence(0.95F);
  for (int index = 0; index < 3; ++index) {
    hand->add_landmarks()->set_x(0.1F * static_cast<float>(index + 1));
  }
  assert(bridge.ingest(bytes(envelope.SerializeAsString())));
  const auto second = bridge.newer_than(first->first);
  assert(second && second->first == 2 && second->second.capture_time_us == 2345);
  assert(second->second.players.size() == 1);
  assert(second->second.players[0].x == 0.6F);
  assert(second->second.players[0].y == 0.7F);
  assert(second->second.players[0].confidence == 0.95F);
  assert(second->second.players[0].gripping);
  assert(second->second.players[0].landmarks.size() == 3);

  frame->clear_persons();
  frame->clear_hands();
  frame->set_capture_time_us(3456);
  auto* standalone = frame->add_hands();
  standalone->set_id(42);
  standalone->set_confidence(0.88F);
  standalone->mutable_center()->set_x(0.2F);
  standalone->mutable_center()->set_y(0.3F);
  assert(bridge.ingest(bytes(envelope.SerializeAsString())));
  const auto third = bridge.newer_than(second->first);
  assert(third && third->second.players.size() == 1);
  assert(third->second.players[0].id == 42);
  assert(third->second.players[0].x == 0.2F);
}
