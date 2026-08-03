#pragma once
#include <cstdint>
#include <mutex>
#include <optional>
#include <utility>

namespace moca {
template <class T> class LatestValue {
 public:
  std::uint64_t replace(T value) {
    std::scoped_lock lock(mutex_);
    value_ = std::move(value);
    return ++sequence_;
  }
  std::optional<std::pair<std::uint64_t, T>> newer_than(std::uint64_t sequence) const {
    std::scoped_lock lock(mutex_);
    if (!value_ || sequence_ <= sequence) return std::nullopt;
    return std::pair{sequence_, *value_};
  }
 private:
  mutable std::mutex mutex_;
  std::optional<T> value_;
  std::uint64_t sequence_{0};
};
}
