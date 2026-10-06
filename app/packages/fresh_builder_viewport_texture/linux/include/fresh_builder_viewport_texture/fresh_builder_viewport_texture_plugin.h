#ifndef FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT   __attribute__((visibility("default")))
#else
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT
#endif

FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT
void fresh_builder_viewport_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif
