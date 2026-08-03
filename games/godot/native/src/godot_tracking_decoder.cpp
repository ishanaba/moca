#include "moca/godot/godot_tracking_decoder.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <cstddef>
#include <cstring>
#include <span>

namespace moca::godot {

void TrackingDecoder::_bind_methods() {
  ::godot::ClassDB::bind_method(::godot::D_METHOD("ingest", "payload"),
                                &TrackingDecoder::ingest);
  ::godot::ClassDB::bind_method(::godot::D_METHOD("poll", "after_sequence"),
                                &TrackingDecoder::poll);
  ::godot::ClassDB::bind_method(::godot::D_METHOD("poll_video", "after_sequence"),
                                &TrackingDecoder::poll_video);
}

::godot::Dictionary TrackingDecoder::poll_video(std::int64_t after_sequence) const {
  const auto snapshot = bridge_.video_newer_than(static_cast<std::uint64_t>(after_sequence));
  if (!snapshot) return {};
  ::godot::PackedByteArray jpeg;
  jpeg.resize(static_cast<std::int64_t>(snapshot->second.jpeg.size()));
  if (!snapshot->second.jpeg.empty()) {
    std::memcpy(jpeg.ptrw(), snapshot->second.jpeg.data(), snapshot->second.jpeg.size());
  }
  ::godot::Dictionary result;
  result["sequence"] = static_cast<std::int64_t>(snapshot->first);
  result["capture_time_us"] = static_cast<std::int64_t>(snapshot->second.capture_time_us);
  result["jpeg"] = jpeg;
  return result;
}

bool TrackingDecoder::ingest(const ::godot::PackedByteArray& payload) {
  const auto* data = reinterpret_cast<const std::byte*>(payload.ptr());
  return bridge_.ingest(std::span<const std::byte>(data, payload.size()));
}

::godot::Dictionary TrackingDecoder::poll(std::int64_t after_sequence) const {
  const auto snapshot = bridge_.newer_than(static_cast<std::uint64_t>(after_sequence));
  if (!snapshot) return {};
  ::godot::Array players;
  for (const auto& player : snapshot->second.players) {
    ::godot::Dictionary value;
    value["id"] = player.id;
    value["x"] = player.x;
    value["y"] = player.y;
    value["confidence"] = player.confidence;
    players.push_back(value);
  }
  ::godot::Dictionary result;
  result["sequence"] = static_cast<std::int64_t>(snapshot->first);
  result["capture_time_us"] = static_cast<std::int64_t>(snapshot->second.capture_time_us);
  result["source"] = snapshot->second.source.c_str();
  result["players"] = players;
  return result;
}

}  // namespace moca::godot
