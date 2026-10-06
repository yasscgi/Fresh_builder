#ifndef FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT   __attribute__((visibility("default")))
#else
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT
#endif

#define FRESH_BUILDER_VIEWPORT_TEXTURE_TYPE_PLUGIN \
  (fresh_builder_viewport_texture_plugin_get_type())

G_DECLARE_FINAL_TYPE(
    FreshBuilderViewportTexturePlugin,
    fresh_builder_viewport_texture_plugin,
    FRESH_BUILDER_VIEWPORT_TEXTURE,
    PLUGIN,
    GObject)

FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT
void fresh_builder_viewport_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif
