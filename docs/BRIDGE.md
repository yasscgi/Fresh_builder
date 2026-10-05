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

This keeps Flutter free from rig math and GPU backend selection.

## Runtime rule

Flutter may request durable state changes and gesture boundaries. Continuous IK/FK state remains native. We must not serialize the full character pose from Rust to Dart for every pointer move.

## WGPU stage

builder_render already owns WGPU adapter selection. The next rendering step is a native viewport surface/texture transport; GPU frames should not be PNG-encoded and copied through Dart for every frame.
