#include "moca/transport/websocket_server.hpp"

#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/websocket.hpp>

#include <utility>

namespace moca {
namespace asio = boost::asio;
namespace beast = boost::beast;
namespace websocket = beast::websocket;
using tcp = asio::ip::tcp;

struct WebSocketServer::State {
  explicit State(std::uint16_t port)
      : acceptor(context, tcp::endpoint(tcp::v4(), port)), socket(context) {
    acceptor.set_option(asio::socket_base::reuse_address(true));
  }
  asio::io_context context;
  tcp::acceptor acceptor;
  websocket::stream<tcp::socket> socket;
};

WebSocketServer::WebSocketServer(std::uint16_t port) : state_(std::make_unique<State>(port)) {}
WebSocketServer::~WebSocketServer() = default;

bool WebSocketServer::accept(std::string& error) {
  beast::error_code code;
  state_->acceptor.accept(state_->socket.next_layer(), code);
  if (code) {
    error = code.message();
    return false;
  }
  state_->socket.accept(code);
  if (code) {
    error = code.message();
    return false;
  }
  state_->socket.binary(true);
  return true;
}

bool WebSocketServer::send(std::span<const std::uint8_t> payload, std::string& error) {
  beast::error_code code;
  state_->socket.write(asio::buffer(payload.data(), payload.size()), code);
  if (code) {
    error = code.message();
    return false;
  }
  return true;
}

}  // namespace moca
