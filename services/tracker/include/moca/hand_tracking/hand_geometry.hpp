#pragma once

#include "moca/inference/backend.hpp"

#include <span>

namespace moca {

Keypoint palm_center(std::span<const Keypoint> landmarks);
bool is_gripping(std::span<const Keypoint> landmarks);

}  // namespace moca
