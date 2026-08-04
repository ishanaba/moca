#pragma once

#include "moca/hand_tracking/backend.hpp"

namespace moca {

std::vector<HandObservation> associate_hands_to_wrists(
    std::vector<HandObservation> hands,
    std::span<const TrackedDetection> persons,
    float maximum_distance = 0.18F);

}  // namespace moca
