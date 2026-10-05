# Fresh Builder Native Architecture

## Goal

One Builder codebase targeting Windows, macOS, Linux, Android and iOS/iPadOS.

## Ownership

Flutter owns presentation and interaction composition: responsive layouts, asset/category navigation, tool rails, inspectors, theme, cloud UI and pointer/touch gesture intent.

Rust owns deterministic Builder logic: design state, undo/redo, transient gestures, Rig Profile V3, semantic bones, IK/FK math and constraints, cache policy and later printable export.

The production viewport renderer will use wgpu behind a narrow native bridge.

Target rendering backends:
- Windows: Direct3D 12
- macOS/iOS: Metal
- Linux/Android: Vulkan where available

## Interaction invariant

Continuous IK/FK gestures use live native scene state.

pointer down
- begin transient edit
- lock viewport navigation

pointer move
- update live Rust rig
- solve
- render
- do not commit full Flutter state

pointer up
- commit one durable pose patch
- commit one undo entry
- unlock viewport

This preserves the same core rule used by FreshSTL Builder: durable application state is not the per-frame pose transport.

## Rig V3 compatibility

The native app keeps the freshstl_mixamo_rig_v3 semantic contract:
- semantic source bone
- semantic parent
- rest transform
- primary axis
- hinge axis
- bone length
- confidence
- IK upper/lower/effector
- stable pole direction

Imported geometry remains authoritative for actual transforms and lengths. Authored Rig V3 metadata expresses semantic intent and validation expectations.

## Delivery phases

1. Core state and responsive Flutter shell.
2. Flutter/Rust bridge.
3. wgpu viewport, camera, picking and navigation cube.
4. Rig Profile V3 import and live IK/FK.
5. FreshSTL/Supabase authentication, products, assets and saved designs.
6. STL/3MF printable export.
7. Articulated and Surface SVG modes.
