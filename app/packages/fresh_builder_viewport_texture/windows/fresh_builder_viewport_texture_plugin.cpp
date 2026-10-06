#include "fresh_builder_viewport_texture_plugin.h"

#include <windows.h>

#include <string>
#include <utility>

namespace fresh_builder_viewport_texture {

namespace {
constexpr char kChannelName[] = "fresh_builder/viewport_texture";
constexpr wchar_t kRustLibraryName[] = L"fresh_builder_rust.dll";
}  // namespace

void FreshBuilderViewportTexturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin =
      std::make_unique<FreshBuilderViewportTexturePlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](
          const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FreshBuilderViewportTexturePlugin::FreshBuilderViewportTexturePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

FreshBuilderViewportTexturePlugin::~FreshBuilderViewportTexturePlugin() {
  DisposeTexture();
  if (owns_rust_module_ && rust_module_ != nullptr) {
    FreeLibrary(rust_module_);
  }
}

bool FreshBuilderViewportTexturePlugin::ResolveRustBridge() {
  if (capture_enabled_ != nullptr && copy_latest_frame_ != nullptr) {
    return true;
  }

  rust_module_ = GetModuleHandleW(kRustLibraryName);
  if (rust_module_ == nullptr) {
    rust_module_ = LoadLibraryW(kRustLibraryName);
    owns_rust_module_ = rust_module_ != nullptr;
  }
  if (rust_module_ == nullptr) {
    return false;
  }

  capture_enabled_ = reinterpret_cast<CaptureEnabledFn>(
      GetProcAddress(rust_module_, "fresh_builder_frame_capture_enabled"));
  copy_latest_frame_ = reinterpret_cast<CopyLatestFrameFn>(
      GetProcAddress(rust_module_, "fresh_builder_copy_latest_frame"));

  return capture_enabled_ != nullptr && copy_latest_frame_ != nullptr;
}

bool FreshBuilderViewportTexturePlugin::CreateTexture() {
  if (texture_id_ >= 0) {
    return true;
  }
  if (!ResolveRustBridge()) {
    return false;
  }

  texture_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture(
          [this](size_t width, size_t height)
              -> const FlutterDesktopPixelBuffer* {
            return CopyPixelBuffer(width, height);
          }));

  texture_id_ =
      registrar_->texture_registrar()->RegisterTexture(texture_.get());
  if (texture_id_ < 0) {
    texture_.reset();
    return false;
  }

  capture_enabled_(true);
  return true;
}

void FreshBuilderViewportTexturePlugin::DisposeTexture() {
  if (capture_enabled_ != nullptr) {
    capture_enabled_(false);
  }

  if (texture_id_ >= 0 && registrar_ != nullptr) {
    registrar_->texture_registrar()->UnregisterTexture(
        texture_id_, nullptr);
  }

  texture_id_ = -1;
  texture_.reset();
  std::scoped_lock lock(frame_mutex_);
  pixels_.clear();
  pixel_buffer_ = {};
}

const FlutterDesktopPixelBuffer*
FreshBuilderViewportTexturePlugin::CopyPixelBuffer(
    size_t width, size_t height) {
  if (copy_latest_frame_ == nullptr) {
    return nullptr;
  }

  std::scoped_lock lock(frame_mutex_);

  uint32_t frame_width = 0;
  uint32_t frame_height = 0;
  uint64_t generation = generation_;
  const size_t required = copy_latest_frame_(
      nullptr, 0, &frame_width, &frame_height, &generation);

  if (required == 0 || frame_width == 0 || frame_height == 0) {
    return nullptr;
  }

  pixels_.resize(required);
  const size_t copied = copy_latest_frame_(
      pixels_.data(), pixels_.size(),
      &frame_width, &frame_height, &generation);

  if (copied != required) {
    return nullptr;
  }

  generation_ = generation;
  pixel_buffer_.buffer = pixels_.data();
  pixel_buffer_.width = frame_width;
  pixel_buffer_.height = frame_height;
  pixel_buffer_.release_callback = nullptr;
  pixel_buffer_.release_context = nullptr;
  return &pixel_buffer_;
}

void FreshBuilderViewportTexturePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "create") {
    if (!CreateTexture()) {
      result->Error(
          "native_texture_unavailable",
          "Could not resolve the Fresh Builder Rust frame bridge.");
      return;
    }
    result->Success(flutter::EncodableValue(texture_id_));
    return;
  }

  if (method == "markFrame") {
    if (texture_id_ >= 0) {
      registrar_->texture_registrar()->MarkTextureFrameAvailable(texture_id_);
    }
    result->Success();
    return;
  }

  if (method == "dispose") {
    DisposeTexture();
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace fresh_builder_viewport_texture
