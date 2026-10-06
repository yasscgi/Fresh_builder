#ifndef FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

namespace fresh_builder_viewport_texture {

class FreshBuilderViewportTexturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FreshBuilderViewportTexturePlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~FreshBuilderViewportTexturePlugin() override;

  FreshBuilderViewportTexturePlugin(
      const FreshBuilderViewportTexturePlugin&) = delete;
  FreshBuilderViewportTexturePlugin& operator=(
      const FreshBuilderViewportTexturePlugin&) = delete;

 private:
  using CaptureEnabledFn = void(__cdecl*)(bool);
  using CopyLatestFrameFn = size_t(__cdecl*)(
      uint8_t*, size_t, uint32_t*, uint32_t*, uint64_t*);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool ResolveRustBridge();
  bool CreateTexture();
  void DisposeTexture();
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;

  HMODULE rust_module_ = nullptr;
  bool owns_rust_module_ = false;
  CaptureEnabledFn capture_enabled_ = nullptr;
  CopyLatestFrameFn copy_latest_frame_ = nullptr;

  std::mutex frame_mutex_;
  std::vector<uint8_t> pixels_;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  uint64_t generation_ = 0;
};

}  // namespace fresh_builder_viewport_texture

#endif
