#pragma once

#include <cstdint>
#include <memory>
#include <span>
#include <string>

namespace moca {

class WebSocketServer {
 public:
  explicit WebSocketServer(std::uint16_t port);
  ~WebSocketServer();
  WebSocketServer(const WebSocketServer&) = delete;
  WebSocketServer& operator=(const WebSocketServer&) = delete;

  [[nodiscard]] bool accept(std::string& error);
  [[nodiscard]] bool send(std::span<const std::uint8_t> payload, std::string& error);

 private:
  struct State;
  std::unique_ptr<State> state_;
};

}  // namespace moca
