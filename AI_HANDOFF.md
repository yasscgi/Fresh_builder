# Fresh Builder Native — AI Handoff

Last audited: 2026-10-07
Repository: yasscgi/Fresh_builder
Production branch audited: main
Production baseline: 9ba6299dd5cb28c35430d7e58ecf4cc4a52d9c49
Active WIP: PR #17, feat/flutter-rig-session, head ab0c25f19ee5476d2f26c1dbb3dc9c3b38b20b04

## Read this first

Do not assume an item is complete because a type or UI button exists. The project currently has three distinct layers:
1. Flutter interaction/UI.
2. Rust deterministic Builder/rig state.
3. WGPU render state.

The largest unfinished integration is connecting rig edits all the way through these layers so FK/IK visibly deforms the rendered skinned character.

## Current main: confirmed implemented

- Responsive Flutter Builder shell and FreshSTL-style light/dark UI.
- Builder transform rail and navigation/view controls.
- Supabase auth/data flow, product/config/category/asset loading and protected signed asset URL flow.
- Versioned local asset disk cache.
- GLB/glTF native scene decode with positions, normals, UVs, joints and weights.
- Skeleton hierarchy/local matrices/inverse bind data in RenderScene.
- Persistent NativeViewportSession.
- WGPU offscreen renderer, camera matrices, depth testing and indexed scene drawing.
- Desktop Flutter Texture presentation on Windows, Linux and macOS.
- Native camera orbit/zoom/view presets.
- Rust BuilderHistory transient editing model.
- Rig Profile V3 semantic types and two-bone IK math.

## Critical verified problems in main

### P0 — main.dart compile/scope defect
_FreshBuilderAppState._preloadBaseCharacter() references _assetCache, _workspace and _nativeViewport, but those fields belong to _BuilderPageState. PR #17 moves the method into the correct State class. Treat this as a blocker in main until fixed/merged.

### P0 — no GPU skinning
RenderVertex/GpuVertex carries joints and weights, and RenderScene carries a skeleton, but mesh.wgsl ignores joints/weights and transforms input.position directly by camera.view_proj. MeshPipeline only binds the camera uniform. There is no joint palette buffer/bind group and no skin matrix application.

Consequence: even a correct FK/IK pose state cannot visually deform the character yet.

### P0 — rig state is not connected to renderer
main has Flutter RigMode/UI state, while WGPU has independent scene buffers. There is no production path:
Flutter rig gesture -> native rig pose -> skeleton local/global transforms -> joint palette -> redraw.

### P1 — PR #17 is WIP, not production
PR #17 adds NativeRigSession with explicit IK/FK modes, selected bone, transient FK/IK gesture state, undo/redo and hand state. It also fixes the preload scope bug.
GitHub reports the PR mergeable at the Git level, but workflow run 37510884929 completed with failure in all five jobs: native-core, flutter-bridge, windows-texture, linux-texture, macos-texture. Logs were not retrievable during this audit. Re-run CI and diagnose the first real error before merging.

### P1 — FBX is not decoded
The current native scene path explicitly reports needs_fbx_decoder. GLB/glTF is the working native import route. Do not claim FBX support until a decoder/conversion path is implemented and tested.

### P1 — mobile native texture presentation is incomplete
The repository has explicit native Flutter texture backends/CI for Windows, Linux and macOS. Android/iOS native texture presentation is still a separate milestone.

### P1 — picking/gizmos are not end-to-end
The architecture calls for picking and rig gizmos, but there is not yet a complete renderer-backed bone selection + FK rotation gizmo + IK handle pipeline.

## PR #17 content

Files changed:
- app/lib/main.dart
- app/rust/src/api/mod.rs
- app/rust/src/api/rig.rs

NativeRigSession provides:
- BridgeRigMode: None / Ik / Fk
- selected bone
- hand open state
- begin/update/commit/cancel gesture
- FK Euler state by bone
- IK target state by effector/bone key
- undo/redo
- PoseState export

Important: this is state/history infrastructure. It does NOT implement GPU skinning or visible skeleton deformation.

## Next implementation order

1. Make PR #17 green.
   - Re-run CI.
   - Fix Rust/FRB codegen/analyzer/test errors.
   - Confirm all desktop jobs pass.
   - Merge only after green.

2. Make NativeRigSession the rig source of truth.
   - Generate FRB Dart API for api/rig.rs.
   - Add NativeRigController in Flutter.
   - Remove duplicated/divergent local rig state where possible.
   - Wire IK/FK/Open/Close and undo/redo.
   - During pose gesture call workspace.beginPoseGesture(); commit/cancel must unlock navigation.

3. Add rest-pose skinning to WGPU before interactive FK.
   - Preserve skeleton on GPU scene, not only joint_count.
   - Compute global bind/current transforms.
   - Compute skin matrices: current_global * inverse_bind.
   - Add joint palette GPU buffer and bind group.
   - Update mesh.wgsl to blend up to 4 joint matrices by weights.
   - Correctly transform normals.
   - Add tests for identity/rest pose.

4. Implement FK end-to-end.
   - Map selected semantic/source bone to skeleton joint index.
   - Convert gizmo rotation to a local joint delta.
   - Recompute descendants/global matrices.
   - Upload palette only; do not re-upload mesh.
   - Render on every coalesced pose update.
   - Commit one history entry on pointer release.

5. Implement IK end-to-end.
   - Resolve Rig V3 chain.
   - Use real rest/current joint positions and stable pole.
   - Convert two-bone IK result into joint rotations, not only solved points.
   - Respect hinge/primary axes and limits.
   - Upload joint palette and redraw.
   - IK mode should expose only relevant effectors/controls.

6. Picking and gizmos.
   - Bone/control picking must be separate from camera orbit.
   - FK: show selectable bones and rotation gizmo.
   - IK: show effectors/handles only.
   - Move/Rotate/Scale tool rail continues to affect selected MODEL/asset, not rig bones.
   - Mobile pointer capture must prevent a rig drag from orbiting the camera.

7. Platform completion.
   - Android texture backend.
   - iOS/iPadOS texture backend.
   - touch gesture tests and lifecycle/context-loss tests.

8. Import/export.
   - Decide FBX decoder strategy or make uploader reliably provide GLB for native Builder.
   - Implement printable STL/3MF export only after transforms/pose are authoritative.
   - Later: articulated and Surface SVG modes.

## Invariants — do not break

- Flutter owns UI/gesture intent; Rust owns deterministic rig/design state.
- Per-frame pose changes must not rebuild full Flutter application state.
- Continuous pose drag = one undo entry.
- Navigation is locked while manipulating rig gizmos.
- Asset transform tools are not IK/FK controls.
- Never ship Supabase service-role/secret keys in the app.
- Protected assets stay behind RLS + builder-asset-url signed URLs.
- Keep Rig V2 as legacy; do not silently treat it as Rig V3.
- Avoid duplicate rig implementations in Flutter and Rust.
- Do not re-download unchanged cached assets.
- Do not re-upload static mesh buffers for every pose frame; update joint palette only.

## Definition of “IK/FK complete”

Do not mark IK/FK complete until all are true:
- a real Rig V3 character loads;
- bone/control selection works;
- FK drag visibly deforms the correct bone and descendants;
- IK hand and foot targets visibly solve the correct chains;
- camera does not rotate during rig drag;
- release creates exactly one undo step;
- undo/redo visibly restores pose;
- hand open/close reaches the real character rig/morph implementation;
- desktop and mobile touch/mouse behavior is tested;
- no duplicate old rig path remains.

## Validation commands

Rust reusable core:
cd rust && cargo test --workspace

Bridge generation:
cd app && flutter_rust_bridge_codegen generate

Flutter-facing Rust:
cd app/rust && cargo test

Flutter:
cd app && flutter analyze && flutter test

Desktop build checks:
flutter build windows --debug
flutter build linux --debug
flutter build macos --debug

## Handoff rule for future AI sessions

Before coding:
1. Read this file.
2. Read docs/CODE_AUDIT_2026-10-07.md.
3. Check current main HEAD and open PRs; do not assume the hashes above are still latest.
4. Run/inspect CI before claiming a stage works.
5. Update both reference files after every meaningful milestone with: completed, remaining, known failures, next exact step.
