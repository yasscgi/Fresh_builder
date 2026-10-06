#ifndef FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_IMPL
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FRESH_BUILDER_VIEWPORT_TEXTURE_PLUGIN_EXPORT void
FreshBuilderViewportTexturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}
#endif

#endif
