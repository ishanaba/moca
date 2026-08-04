#include "moca/hand_tracking/association.hpp"

#include <algorithm>
#include <cstddef>
#include <vector>

namespace moca {

std::vector<HandObservation> associate_hands_to_wrists(
    std::vector<HandObservation> hands,
    std::span<const TrackedDetection> persons,
    float maximum_distance) {
  struct Candidate {
    std::size_t hand;
    std::size_t person;
    bool right;
    float distance_squared;
  };
  std::vector<Candidate> candidates;
  const float maximum_squared = maximum_distance * maximum_distance;
  for (std::size_t hand_index = 0; hand_index < hands.size(); ++hand_index) {
    for (std::size_t person_index = 0; person_index < persons.size(); ++person_index) {
      for (const int wrist_index : {9, 10}) {
        const auto& wrist = persons[person_index].detection.keypoints[wrist_index];
        if (wrist.confidence < 0.15F) continue;
        const float dx = hands[hand_index].center.x - wrist.x;
        const float dy = hands[hand_index].center.y - wrist.y;
        const float distance_squared = dx * dx + dy * dy;
        if (distance_squared <= maximum_squared)
          candidates.push_back({hand_index, person_index, wrist_index == 10, distance_squared});
      }
    }
  }
  std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
    return left.distance_squared < right.distance_squared;
  });
  std::vector<bool> used_hands(hands.size());
  std::vector<bool> used_wrists(persons.size() * 2);
  std::vector<HandObservation> associated;
  for (const auto& candidate : candidates) {
    const std::size_t wrist_slot = candidate.person * 2 + (candidate.right ? 1 : 0);
    if (used_hands[candidate.hand] || used_wrists[wrist_slot]) continue;
    used_hands[candidate.hand] = true;
    used_wrists[wrist_slot] = true;
    auto hand = std::move(hands[candidate.hand]);
    const auto& person = persons[candidate.person];
    const auto& wrist = person.detection.keypoints[candidate.right ? 10 : 9];
    hand.person_id = person.id + 1;
    hand.id = person.id * 2 + (candidate.right ? 2 : 1);
    hand.confidence *= wrist.confidence * person.detection.confidence;
    hand.center.confidence = hand.confidence;
    associated.push_back(std::move(hand));
  }
  std::sort(associated.begin(), associated.end(), [](const auto& left, const auto& right) {
    return left.id < right.id;
  });
  return associated;
}

}  // namespace moca
