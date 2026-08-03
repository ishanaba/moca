#pragma once

#include "moca/godot/tracking_bridge.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace moca::godot {

class TrackingDecoder : public ::godot::RefCounted {
  GDCLASS(TrackingDecoder, ::godot::RefCounted)

 public:
  bool ingest(const ::godot::PackedByteArray& payload);
  [[nodiscard]] ::godot::Dictionary poll(std::int64_t after_sequence) const;
  [[nodiscard]] ::godot::Dictionary poll_video(std::int64_t after_sequence) const;

 protected:
  static void _bind_methods();

 private:
  TrackingBridge bridge_;
};

}  // namespace moca::godot
