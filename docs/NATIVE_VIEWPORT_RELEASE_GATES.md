# Native viewport acceptance gates

The native Builder currently allocates an offscreen WGPU texture, uploads GLB/GLTF vertex and index buffers, and updates camera state through flutter_rust_bridge. **This does not yet display GPU pixels in Flutter.** The Flutter CustomPainter is still a placeholder.

## Release gates (all mandatory)

1. Render actual mesh geometry with depth testing and camera view/projection matrices into the WGPU render target. A clear pass or buffer upload alone does not count.
2. Create a Flutter Texture-compatible platform plugin for Windows, macOS, Linux, Android, and iOS. Handle texture lifecycle, resize, frame availability, app pause/resume, and device loss. Do not transfer PNG frames or entire pose state over Dart every frame.
3. Connect Flutter Texture(textureId) to the native producer and verify physical pixels and logical dimensions on each platform. Verify DX12, Metal, and Vulkan backends where supported.
4. Render base character and attachment scenes together, including proper slot replacement, transform hierarchy, bounds, and camera framing. Test duplicate selection and switching products while downloads are in flight.
5. Support FBX natively without silently converting away rigs. Preserve skeleton, skin weights, rest transforms, and FreshSTL Rig V3 metadata.
6. Add automated Rust unit tests, Flutter widget tests, platform smoke tests, and golden/reference frames. Fail CI on actual build/test errors; investigate runner failures that occur before checkout separately.
7. Verify release builds on Windows, macOS, Linux, Android, and iOS; iOS requires macOS/Xcode.

## Current risks to address

- Scene registry buffers are not yet drawn.
- UI may report GPU ready when data is uploaded but nothing is visible.
- Asset download/import operations can race with product switching; use generation IDs/cancellation.
- Flutter/Rust bridge generation and initialization need compiler validation.
- Existing GitHub Actions jobs have previously failed before their first step, so passing CI has not been demonstrated.

Do not call this viewport production-ready or merge a rendering implementation without evidence of platform validation.
