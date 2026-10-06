# Flutter / Rust Bridge

Fresh Builder uses flutter_rust_bridge 2.13.x as the generated boundary between Dart and Rust.

## Layout

- app/rust: Flutter-facing Rust crate.
- rust/crates/builder_core: renderer-independent Builder state, rig and IK logic.
- rust/crates/builder_render: WGPU runtime/rendering code.
- app/lib/src/rust: generated Dart glue after codegen.

## Generate

From the repository root:

Windows:

    powershell -ExecutionPolicy Bypass -File scripts/generate_bridge.ps1

macOS/Linux:

    bash scripts/generate_bridge.sh

The codegen configuration is stored in app/flutter_rust_bridge.yaml.

## Public native API

The first bridge contract exposes:

- core_status(): reports Builder design and Rig V3 contract versions.
- solve_ik_preview(): calls the real builder_core two-bone solver.
- gpu_status(): asynchronously asks WGPU for a high-performance adapter.
- viewport_smoke_test(width, height): creates a real WGPU device, allocates an RGBA8 viewport render target, submits a render pass, and reports the active GPU/backend.

This keeps Flutter free from rig math and GPU backend selection.

## Runtime rule

Flutter may request durable state changes and gesture boundaries. Continuous IK/FK state remains native. We must not serialize the full character pose from Rust to Dart for every pointer move.

## WGPU stage

builder_render now owns WGPU adapter/device creation, a resizable offscreen viewport target, a real clear render pass, and native camera state. The remaining integration step is native Flutter texture/surface transport; GPU frames must not be PNG-encoded and copied through Dart for every frame.


## Flutter native viewport controller

The Flutter workspace now owns one `NativeViewportController` for the lifetime of the Builder page.

It:
- initializes one persistent `NativeViewportSession`;
- resizes the native render target using logical size × device pixel ratio;
- coalesces orbit and zoom deltas so pointer events do not create an unbounded FFI backlog;
- maps semantic Front/Back/Left/Right/Top/Bottom controls to Rust `ViewPreset`;
- keeps direct viewport orbit on desktop while mobile rotation remains navigation-cube driven;
- queues scene loads that arrive before WGPU initialization completes.

## Native scene registry

`NativeViewportSession` stores GPU scenes by Builder scene key instead of one replace-all scene.

Single-selection categories use a stable role/category/slot key so selecting a new Hat or Stand replaces the previous item. Multi-selection categories use the individual selection key so multiple objects can coexist.

The base character is cached and queued automatically when a Builder product is opened.

Current native import readiness:
- GLB/GLTF: decoded and uploaded into WGPU vertex/index buffers.
- FBX: retained as FBX and reported as `needs_fbx_decoder`; no lossy FBX-to-GLB conversion is performed.
- Other formats: kept explicit as unsupported until their native importer is implemented.

The GPU render target is still offscreen. Platform texture/surface transport remains a separate step; frames must not be PNG-encoded and copied through Dart each frame.


## Native Assets build integration

The Flutter app now uses the flutter_rust_bridge 2.13 Native Assets backend contract directly:

- app/hook/build.dart invokes FlutterRustBridgeNativeAssetsBuilder with cratePath: rust.
- app/rust/rust-toolchain.toml pins Rust 1.93.1 and the supported desktop/mobile targets.
- app/pubspec.yaml includes flutter_rust_bridge_hooks 2.13.0 and requires Dart >= 3.9.2.

This means Flutter builds own compilation and bundling of fresh_builder_rust. Generated Dart bridge code is still produced by flutter_rust_bridge_codegen generate and is not manually maintained.

## Real WGPU frame rendering

ViewportRenderer now owns:
- a color render target;
- a Depth32Float depth target;
- MeshPipeline;
- camera uniform uploads;
- indexed draws for every registered GpuScene.

NativeViewportSession automatically redraws after:
- viewport resize;
- GLB/GLTF scene insertion/removal;
- scene clear;
- orbit;
- zoom;
- semantic view preset changes.

The remaining display boundary is exporting/presenting the offscreen GPU target to Flutter Texture/platform texture without routing full frames through Dart.


## Windows Flutter Texture presentation

The first platform presentation implementation is now Windows.

Data flow:
1. Rust/WGPU renders the scene into the offscreen RGBA8 target.
2. The Windows Flutter plugin registers a PixelBufferTexture.
3. Creating the texture enables native frame capture through exported C ABI symbols in fresh_builder_rust.
4. After coalesced camera/scene updates, Flutter asks Rust to publish one latest frame, then sends only markFrame over the method channel.
5. The Windows texture callback copies the already-published native frame directly into Flutter's external texture buffer. Full frame bytes never travel through Dart.

The readback is intentionally isolated behind capture_enabled so mobile/fallback builds and headless tests do not pay the GPU->CPU cost.

This is an MVP presentation bridge. The next Windows optimization is Flutter's GPU surface texture path using a DXGI shared handle or D3D11 texture so the GPU->CPU readback can be removed entirely.

macOS/Linux/Android/iOS remain on the Flutter fallback until their native texture implementations are added.


## Linux and macOS Flutter Texture presentation

The same `fresh_builder/viewport_texture` method-channel contract now has native desktop implementations on Linux and macOS.

Linux:
- `FlPixelBufferTexture` registered through `FlTextureRegistrar`;
- the plugin resolves the already-loaded `libfresh_builder_rust.so` first with `RTLD_NOLOAD`;
- frame bytes are copied directly from the Rust C ABI into the native texture buffer;
- no image/frame payload crosses Dart.

macOS:
- `FlutterTexture` backed by a reusable `CVPixelBuffer`;
- the plugin resolves the already-loaded `libfresh_builder_rust.dylib` from the app Frameworks directory first;
- the WGPU RGBA frame is converted natively to the BGRA pixel format accepted by Flutter's Darwin texture API;
- Dart still receives only the texture ID and frame-available control messages.

The current desktop presentation path is correctness-first and uses GPU-to-CPU readback once per coalesced interaction. Windows can later move to DXGI/D3D11 shared GPU surfaces; macOS can move to IOSurface/Metal zero-copy; Linux can move to an embedder-supported GPU texture path when available.
