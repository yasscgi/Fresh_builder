#include "include/fresh_builder_viewport_texture/fresh_builder_viewport_texture_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fresh_builder_viewport_texture_plugin.h"

void FreshBuilderViewportTexturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fresh_builder_viewport_texture::FreshBuilderViewportTexturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
