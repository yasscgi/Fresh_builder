#include "include/fresh_builder_viewport_texture/fresh_builder_viewport_texture_plugin.h"

#include <dlfcn.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

namespace {

constexpr char kChannelName[] = "fresh_builder/viewport_texture";
constexpr char kRustLibraryName[] = "libfresh_builder_rust.so";

using CaptureEnabledFn = void (*)(uint8_t);
using CopyLatestFrameFn =
    size_t (*)(uint8_t*, size_t, uint32_t*, uint32_t*, uint64_t*);

G_DECLARE_FINAL_TYPE(FreshBuilderPixelTexture,
                     fresh_builder_pixel_texture,
                     FRESH_BUILDER,
                     PIXEL_TEXTURE,
                     FlPixelBufferTexture)

struct _FreshBuilderPixelTexture {
  FlPixelBufferTexture parent_instance;
  GMutex mutex;
  std::vector<uint8_t>* pixels;
  CopyLatestFrameFn copy_latest_frame;
  uint64_t generation;
};

G_DEFINE_TYPE(FreshBuilderPixelTexture,
              fresh_builder_pixel_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean fresh_builder_pixel_texture_copy_pixels(
    FlPixelBufferTexture* texture,
    const uint8_t** out_buffer,
    uint32_t* width,
    uint32_t* height,
    GError** error) {
  auto* self = FRESH_BUILDER_PIXEL_TEXTURE(texture);
  if (self->copy_latest_frame == nullptr) {
    return FALSE;
  }

  g_mutex_lock(&self->mutex);

  uint32_t frame_width = 0;
  uint32_t frame_height = 0;
  uint64_t generation = self->generation;
  const size_t required = self->copy_latest_frame(
      nullptr, 0, &frame_width, &frame_height, &generation);

  if (required == 0 || frame_width == 0 || frame_height == 0) {
    g_mutex_unlock(&self->mutex);
    return FALSE;
  }

  self->pixels->resize(required);
  const size_t copied = self->copy_latest_frame(
      self->pixels->data(), self->pixels->size(),
      &frame_width, &frame_height, &generation);

  if (copied != required) {
    g_mutex_unlock(&self->mutex);
    return FALSE;
  }

  self->generation = generation;
  *out_buffer = self->pixels->data();
  *width = frame_width;
  *height = frame_height;

  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static void fresh_builder_pixel_texture_finalize(GObject* object) {
  auto* self = FRESH_BUILDER_PIXEL_TEXTURE(object);
  delete self->pixels;
  self->pixels = nullptr;
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(fresh_builder_pixel_texture_parent_class)->finalize(object);
}

static void fresh_builder_pixel_texture_class_init(
    FreshBuilderPixelTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      fresh_builder_pixel_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = fresh_builder_pixel_texture_finalize;
}

static void fresh_builder_pixel_texture_init(FreshBuilderPixelTexture* self) {
  g_mutex_init(&self->mutex);
  self->pixels = new std::vector<uint8_t>();
  self->copy_latest_frame = nullptr;
  self->generation = 0;
}

}  // namespace

struct _FreshBuilderViewportTexturePlugin {
  GObject parent_instance;
  FlTextureRegistrar* texture_registrar;
  FreshBuilderPixelTexture* texture;
  int64_t texture_id;
  void* rust_module;
  bool owns_rust_module;
  CaptureEnabledFn capture_enabled;
  CopyLatestFrameFn copy_latest_frame;
};

G_DEFINE_TYPE(FreshBuilderViewportTexturePlugin,
              fresh_builder_viewport_texture_plugin,
              g_object_get_type())

static bool resolve_rust_bridge(FreshBuilderViewportTexturePlugin* self) {
  if (self->capture_enabled != nullptr &&
      self->copy_latest_frame != nullptr) {
    return true;
  }

  self->capture_enabled = reinterpret_cast<CaptureEnabledFn>(
      dlsym(RTLD_DEFAULT, "fresh_builder_frame_capture_enabled"));
  self->copy_latest_frame = reinterpret_cast<CopyLatestFrameFn>(
      dlsym(RTLD_DEFAULT, "fresh_builder_copy_latest_frame"));

  if (self->capture_enabled != nullptr &&
      self->copy_latest_frame != nullptr) {
    return true;
  }

  self->rust_module =
      dlopen(kRustLibraryName, RTLD_NOW | RTLD_NOLOAD | RTLD_LOCAL);
  self->owns_rust_module = self->rust_module != nullptr;

  if (self->rust_module == nullptr) {
    self->rust_module = dlopen(kRustLibraryName, RTLD_NOW | RTLD_LOCAL);
    self->owns_rust_module = self->rust_module != nullptr;
  }
  if (self->rust_module == nullptr) {
    return false;
  }

  self->capture_enabled = reinterpret_cast<CaptureEnabledFn>(
      dlsym(self->rust_module, "fresh_builder_frame_capture_enabled"));
  self->copy_latest_frame = reinterpret_cast<CopyLatestFrameFn>(
      dlsym(self->rust_module, "fresh_builder_copy_latest_frame"));

  return self->capture_enabled != nullptr &&
         self->copy_latest_frame != nullptr;
}

static bool create_texture(FreshBuilderViewportTexturePlugin* self) {
  if (self->texture_id >= 0) {
    return true;
  }
  if (!resolve_rust_bridge(self)) {
    return false;
  }

  self->texture = FRESH_BUILDER_PIXEL_TEXTURE(
      g_object_new(fresh_builder_pixel_texture_get_type(), nullptr));
  self->texture->copy_latest_frame = self->copy_latest_frame;

  if (!fl_texture_registrar_register_texture(
          self->texture_registrar, FL_TEXTURE(self->texture))) {
    g_clear_object(&self->texture);
    return false;
  }

  self->texture_id = fl_texture_get_id(FL_TEXTURE(self->texture));
  self->capture_enabled(1);
  return self->texture_id >= 0;
}

static void dispose_texture(FreshBuilderViewportTexturePlugin* self) {
  if (self->capture_enabled != nullptr) {
    self->capture_enabled(0);
  }

  if (self->texture != nullptr && self->texture_registrar != nullptr) {
    fl_texture_registrar_unregister_texture(
        self->texture_registrar, FL_TEXTURE(self->texture));
    g_clear_object(&self->texture);
  }

  self->texture_id = -1;
}

static void handle_method_call(FreshBuilderViewportTexturePlugin* self,
                               FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "create") == 0) {
    if (!create_texture(self)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "native_texture_unavailable",
          "Could not resolve the Fresh Builder Rust frame bridge.",
          nullptr));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_int(self->texture_id)));
    }
  } else if (g_strcmp0(method, "markFrame") == 0) {
    if (self->texture != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(
          self->texture_registrar, FL_TEXTURE(self->texture));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "dispose") == 0) {
    dispose_texture(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN(user_data);
  handle_method_call(self, method_call);
}

static void fresh_builder_viewport_texture_plugin_dispose(GObject* object) {
  auto* self = FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN(object);
  dispose_texture(self);

  g_clear_object(&self->texture_registrar);

  if (self->owns_rust_module && self->rust_module != nullptr) {
    dlclose(self->rust_module);
  }
  self->rust_module = nullptr;
  self->owns_rust_module = false;

  G_OBJECT_CLASS(fresh_builder_viewport_texture_plugin_parent_class)
      ->dispose(object);
}

static void fresh_builder_viewport_texture_plugin_class_init(
    FreshBuilderViewportTexturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose =
      fresh_builder_viewport_texture_plugin_dispose;
}

static void fresh_builder_viewport_texture_plugin_init(
    FreshBuilderViewportTexturePlugin* self) {
  self->texture_registrar = nullptr;
  self->texture = nullptr;
  self->texture_id = -1;
  self->rust_module = nullptr;
  self->owns_rust_module = false;
  self->capture_enabled = nullptr;
  self->copy_latest_frame = nullptr;
}

void fresh_builder_viewport_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* self = FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN(
      g_object_new(fresh_builder_viewport_texture_plugin_get_type(), nullptr));

  self->texture_registrar = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));

  g_autoptr(FlStandardMethodCodec) codec =
      fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      kChannelName,
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(self), g_object_unref);

  g_object_unref(self);
}
