#include <jni.h>
#include <dlfcn.h>

#include <cstdint>
#include <cstring>
#include <vector>

namespace {

using CaptureEnabledFn = void (*)(uint8_t);
using CopyLatestFrameFn =
    size_t (*)(uint8_t*, size_t, uint32_t*, uint32_t*, uint64_t*);

void* g_rust_module = nullptr;
CaptureEnabledFn g_capture_enabled = nullptr;
CopyLatestFrameFn g_copy_latest_frame = nullptr;

bool resolve_rust_bridge() {
  if (g_capture_enabled != nullptr && g_copy_latest_frame != nullptr) {
    return true;
  }

  g_capture_enabled = reinterpret_cast<CaptureEnabledFn>(
      dlsym(RTLD_DEFAULT, "fresh_builder_frame_capture_enabled"));
  g_copy_latest_frame = reinterpret_cast<CopyLatestFrameFn>(
      dlsym(RTLD_DEFAULT, "fresh_builder_copy_latest_frame"));

  if (g_capture_enabled != nullptr && g_copy_latest_frame != nullptr) {
    return true;
  }

  g_rust_module = dlopen("libfresh_builder_rust.so", RTLD_NOW | RTLD_LOCAL);
  if (g_rust_module == nullptr) {
    return false;
  }

  g_capture_enabled = reinterpret_cast<CaptureEnabledFn>(
      dlsym(g_rust_module, "fresh_builder_frame_capture_enabled"));
  g_copy_latest_frame = reinterpret_cast<CopyLatestFrameFn>(
      dlsym(g_rust_module, "fresh_builder_copy_latest_frame"));

  return g_capture_enabled != nullptr && g_copy_latest_frame != nullptr;
}

void write_u32_le(uint8_t* target, uint32_t value) {
  target[0] = static_cast<uint8_t>(value & 0xff);
  target[1] = static_cast<uint8_t>((value >> 8) & 0xff);
  target[2] = static_cast<uint8_t>((value >> 16) & 0xff);
  target[3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_freshstl_fresh_1builder_1viewport_1texture_FreshBuilderViewportTexturePlugin_nativeSetCapture(
    JNIEnv*, jclass, jboolean enabled) {
  if (!resolve_rust_bridge()) {
    return JNI_FALSE;
  }
  g_capture_enabled(enabled == JNI_TRUE ? 1 : 0);
  return JNI_TRUE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_freshstl_fresh_1builder_1viewport_1texture_FreshBuilderViewportTexturePlugin_nativeReadFrame(
    JNIEnv* env, jclass) {
  if (!resolve_rust_bridge()) {
    return nullptr;
  }

  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t generation = 0;
  const size_t required =
      g_copy_latest_frame(nullptr, 0, &width, &height, &generation);
  if (required == 0 || width == 0 || height == 0) {
    return nullptr;
  }

  std::vector<uint8_t> rgba(required);
  const size_t copied = g_copy_latest_frame(
      rgba.data(), rgba.size(), &width, &height, &generation);
  if (copied != required) {
    return nullptr;
  }

  std::vector<uint8_t> packed(8 + required);
  write_u32_le(packed.data(), width);
  write_u32_le(packed.data() + 4, height);
  std::memcpy(packed.data() + 8, rgba.data(), required);

  jbyteArray result = env->NewByteArray(static_cast<jsize>(packed.size()));
  if (result == nullptr) {
    return nullptr;
  }
  env->SetByteArrayRegion(
      result,
      0,
      static_cast<jsize>(packed.size()),
      reinterpret_cast<const jbyte*>(packed.data()));
  return result;
}
