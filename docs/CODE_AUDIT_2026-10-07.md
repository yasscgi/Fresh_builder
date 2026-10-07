# Code Audit — 2026-10-07

## Scope
Audit of Fresh_builder native Flutter/Rust/WGPU architecture at main 9ba6299 plus unmerged PR #17.

## Status scorecard

| Area | Status | Notes |
|---|---|---|
| Flutter responsive shell | Strong foundation | Current FreshSTL-style desktop/mobile chrome exists |
| Supabase/cloud | Implemented foundation | Auth, RLS-backed Builder data, signed protected assets, disk cache |
| GLB/glTF import | Implemented foundation | Geometry + skin attributes + skeleton decoded |
| FBX import | Missing | Current status path says decoder pending |
| Rust Builder core | Good foundation | history, Rig V3 semantics, two-bone IK |
| WGPU camera/render | Implemented foundation | offscreen render, depth, scene draw |
| Desktop texture bridge | Implemented | Windows/Linux/macOS |
| Mobile texture bridge | Missing/incomplete | Android/iOS not covered by current native texture CI |
| Rig edit session | WIP in PR #17 | not in main; CI failed |
| GPU skinning | Missing | shader ignores joints/weights |
| FK visual deformation | Missing | no palette/skeleton update path |
| IK visual deformation | Missing | solver exists but not wired to skeleton/render |
| Picking/bone gizmos | Missing/incomplete | no complete end-to-end path |
| Printable export | Future | architecture phase |
| Articulated/Surface SVG | Future | architecture phase |

## Architecture findings

### Good decisions to preserve
- Narrow Flutter/Rust boundary.
- Native persistent viewport session instead of per-frame FFI object creation.
- Coalesced orbit/zoom updates.
- Protected network authorization outside renderer.
- Versioned disk cache.
- Deterministic transient history model.
- Renderer-independent Rig V3 semantics.
- Desktop frame bytes do not traverse Dart.

### Risks / debt
1. main currently contains a State ownership compile defect in preloadBaseCharacter.
2. Rig UI state and future native rig state can diverge unless NativeRigSession becomes authoritative.
3. Renderer discards useful skeleton detail after upload: GpuScene stores only joint_count, preventing pose updates.
4. Shader vertex contract includes joints/weights but currently wastes them.
5. A CPU readback texture path is correctness-first and can become a performance bottleneck at high resolution/frame rate; zero-copy platform surfaces are a later optimization, not a blocker for rig correctness.
6. CI for PR #17 failed across all jobs. Do not merge blindly.
7. README/architecture text is stale in places: it still describes viewport/camera as a next milestone even though desktop viewport rendering now exists.

## Renderer gap in concrete terms

Current:
RenderScene.skeleton -> upload_scene() -> GpuScene { meshes, joint_count }
mesh.wgsl -> camera * original vertex position

Required:
RenderScene.skeleton
-> retained CPU skeleton/rest pose
-> current local pose
-> global joint matrices
-> skin matrices = global_current * inverse_bind
-> GPU joint palette
-> weighted vertex skinning in WGSL
-> camera transform

This is the shortest technical path to visible FK/IK.

## Suggested module boundaries

Rust:
- builder_core: rig semantics, constraints, history, pose commands.
- builder_render::skeleton_pose (new): matrix hierarchy, local/global pose, palette generation.
- builder_render::gpu_scene: mesh buffers + retained skeleton/palette GPU resources.
- app/rust/api/rig: FRB session/orchestration.
- app/rust/api/builder: viewport/scene orchestration.

Flutter:
- BuilderWorkspaceController: UI navigation/tool locks only.
- NativeViewportController: camera/scenes/frame presentation.
- NativeRigController (new): generated NativeRigSession wrapper and gesture coalescing.
- widgets: emit intent; do not own a second pose model.

## Tests that should be added next

Rust:
- rest palette produces identity deformation.
- parent FK rotation moves child global transform.
- four-weight skin blend is numerically stable.
- zero total weight falls back safely.
- invalid joint index is rejected during scene validation.
- IK target -> joint rotations preserves segment lengths.
- transient FK/IK gesture creates one undo entry.

Flutter:
- switching IK/FK updates native controller.
- pose gesture locks camera navigation.
- commit/cancel always unlocks navigation.
- rig drag never invokes orbit.
- hand toggle round-trips native state.
- controller survives scene replacement/product switch.

Integration:
- known tiny two-joint GLB renders rest pose.
- rotate joint and compare expected deformed vertex.
- resize + pose + texture publish.
- product switch clears old rig/scene state.

## CI note

PR #17 head ab0c25f... had workflow run 37510884929.
Observed conclusions:
- native-core: failure
- flutter-bridge: failure
- windows-texture: failure
- linux-texture: failure
- macos-texture: failure

The logs were unavailable from the connector during this audit. This audit therefore does NOT claim a root cause.

## Immediate next task

Do not start with prettier gizmos. First make PR #17 compile and pass CI. Then implement rest-pose GPU skinning. Only after the skinning palette is proven should FK/IK gizmos be connected to it.
