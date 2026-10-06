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
