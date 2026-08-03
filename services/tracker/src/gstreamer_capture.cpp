#include "moca/capture/gstreamer_capture.hpp"

#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/video-info.h>

#include <cstring>
#include <mutex>
#include <sstream>
#include <utility>

namespace moca {
namespace {
void initialize_gstreamer() {
  static std::once_flag initialized;
  std::call_once(initialized, [] { gst_init(nullptr, nullptr); });
}

std::string message_text(GError* error) {
  if (error == nullptr) return "unknown GStreamer error";
  std::string text = error->message;
  g_error_free(error);
  return text;
}
}  // namespace

struct GStreamerCapture::State {
  explicit State(std::string description) : description(std::move(description)) {}
  std::string description;
  GstElement* pipeline{};
  GstAppSink* sink{};
};

GStreamerCapture::GStreamerCapture(std::string pipeline_description)
    : state_(std::make_unique<State>(std::move(pipeline_description))) {
  initialize_gstreamer();
}

GStreamerCapture::~GStreamerCapture() { stop(); }
GStreamerCapture::GStreamerCapture(GStreamerCapture&&) noexcept = default;
GStreamerCapture& GStreamerCapture::operator=(GStreamerCapture&&) noexcept = default;

bool GStreamerCapture::start(std::string& error) {
  stop();
  GError* parse_error = nullptr;
  state_->pipeline = gst_parse_launch(state_->description.c_str(), &parse_error);
  if (state_->pipeline == nullptr || parse_error != nullptr) {
    error = message_text(parse_error);
    stop();
    return false;
  }
  auto* element = gst_bin_get_by_name(GST_BIN(state_->pipeline), "sink");
  if (element == nullptr || !GST_IS_APP_SINK(element)) {
    if (element != nullptr) gst_object_unref(element);
    error = "pipeline must contain an appsink named sink";
    stop();
    return false;
  }
  state_->sink = GST_APP_SINK(element);
  gst_app_sink_set_emit_signals(state_->sink, false);
  gst_app_sink_set_max_buffers(state_->sink, 1);
  gst_app_sink_set_drop(state_->sink, true);
  gst_base_sink_set_sync(GST_BASE_SINK(state_->sink), false);
  if (gst_element_set_state(state_->pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
    error = "failed to start GStreamer pipeline";
    stop();
    return false;
  }
  return true;
}

void GStreamerCapture::stop() {
  if (state_->pipeline != nullptr) gst_element_set_state(state_->pipeline, GST_STATE_NULL);
  if (state_->sink != nullptr) gst_object_unref(state_->sink);
  if (state_->pipeline != nullptr) gst_object_unref(state_->pipeline);
  state_->sink = nullptr;
  state_->pipeline = nullptr;
}

bool GStreamerCapture::is_running() const { return state_->pipeline != nullptr; }

std::unique_ptr<CapturedFrame> GStreamerCapture::pull(std::chrono::milliseconds timeout,
                                                      std::string& error) {
  if (state_->sink == nullptr) {
    error = "capture is not running";
    return nullptr;
  }
  GstSample* sample = gst_app_sink_try_pull_sample(
      state_->sink, static_cast<GstClockTime>(timeout.count()) * GST_MSECOND);
  if (sample == nullptr) {
    GstBus* bus = gst_element_get_bus(state_->pipeline);
    GstMessage* message = gst_bus_pop_filtered(
        bus, static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
    gst_object_unref(bus);
    if (message != nullptr && GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
      GError* gst_error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &gst_error, &debug);
      error = message_text(gst_error);
      g_free(debug);
    } else {
      error = message != nullptr ? "capture reached end of stream" : "capture timed out";
    }
    if (message != nullptr) gst_message_unref(message);
    return nullptr;
  }

  GstCaps* caps = gst_sample_get_caps(sample);
  GstVideoInfo info{};
  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstMapInfo mapped{};
  if (caps == nullptr || !gst_video_info_from_caps(&info, caps) || buffer == nullptr ||
      !gst_buffer_map(buffer, &mapped, GST_MAP_READ)) {
    error = "could not map captured video frame";
    gst_sample_unref(sample);
    return nullptr;
  }
  auto frame = std::make_unique<CapturedFrame>();
  frame->width = static_cast<int>(GST_VIDEO_INFO_WIDTH(&info));
  frame->height = static_cast<int>(GST_VIDEO_INFO_HEIGHT(&info));
  frame->stride = GST_VIDEO_INFO_PLANE_STRIDE(&info, 0);
  frame->captured_at = std::chrono::steady_clock::now();
  frame->pixels.resize(mapped.size);
  std::memcpy(frame->pixels.data(), mapped.data, mapped.size);
  gst_buffer_unmap(buffer, &mapped);
  gst_sample_unref(sample);
  return frame;
}

std::string GStreamerCapture::camera_pipeline(const std::string& device, int width, int height,
                                              int fps) {
  std::ostringstream pipeline;
  pipeline << "v4l2src device=" << device
           << " ! video/x-raw,width=" << width << ",height=" << height << ",framerate=" << fps
           << "/1 ! videoconvert ! video/x-raw,format=RGB ! appsink name=sink";
  return pipeline.str();
}

}  // namespace moca
