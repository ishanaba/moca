#pragma once

#include "moca/inference/backend.hpp"

#include <memory>

namespace moca {

class OpenVinoYoloPose final : public PoseBackend {
 public:
  OpenVinoYoloPose(const std::string& model_path, std::string device = "CPU",
                   float confidence_threshold = 0.35F);
  ~OpenVinoYoloPose() override;
  OpenVinoYoloPose(const OpenVinoYoloPose&) = delete;
  OpenVinoYoloPose& operator=(const OpenVinoYoloPose&) = delete;

  [[nodiscard]] std::string name() const override;
  [[nodiscard]] std::string device() const override;
  std::vector<Detection> infer(ImageView image) override;

 private:
  struct State;
  std::unique_ptr<State> state_;
};

}  // namespace moca
