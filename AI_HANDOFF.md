# Fresh Builder Native — AI Handoff

Last audited: 2026-10-07
Repository: yasscgi/Fresh_builder
Production branch audited: main
Production baseline: 9ba6299dd5cb28c35430d7e58ecf4cc4a52d9c49
Active WIP: PR #17, feat/flutter-rig-session, head 40c917e268e27de9dabc001afa81cde25dc2ab33

## Read this first

Do not assume an item is complete because a type or UI button exists. The project currently has three distinct layers:
1. Flutter interaction/UI.
2. Rust deterministic Builder/rig state.
3. WGPU render state.

The largest unfinished integration is connecting rig edits all the way through these layers so FK/IK visibly deforms the rendered skinned character.

## Continuation status — 2026-10-07

Completed in active PR #17 after this audit:
- Fixed the existing Rust scene-validation bug that treated `RenderScene::joint_count()` like a field.
- Added `builder_render::skeleton_pose` with hierarchy validation, local/global transforms, rest/current pose state and joint-palette generation.
- Added numerical tests for rest-pose identity, parent/child propagation, four-weight blending, zero-weight fallback, hierarchy cycles and rest-translation-preserving FK deltas.
- `GpuScene` now retains `SkeletonPose`, a GPU joint-palette storage buffer and a bind group.
- `mesh.wgsl` now blends up to four joint matrices and skins position + normal before camera projection.
- Pose changes update the joint palette only; mesh vertex/index buffers are not re-uploaded.
- Added native FK application path: scene key + bone name + Euler delta -> skeleton joint -> palette upload -> redraw.
- Added `NativeRigSession::pose_snapshot()` so FK/IK history can remain authoritative across undo/redo and viewport resync.
- Updated the pipeline for wgpu 30.0.1's optional bind-group-layout entries.
- CI setup actions were removed to rule out third-party Action policy failures.

CI is still blocked before code execution. Latest PR run `37644775789` (run #335) fails all five jobs with `runner_id: 0` and `steps: []`. No runner is assigned, so this run provides no Rust/Flutter compile result. Do not claim the branch is green until GitHub runner allocation is restored and the validation commands below execute.

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

### P0 — no GPU skinning on main; implementation now exists in active PR
The audited main baseline still has no skinning. Active PR #17 now retains the skeleton on `GpuScene`, computes current-global × inverse-bind palettes, uploads them through a storage buffer/bind group, and applies four-weight skinning in `mesh.wgsl`.

This is implemented but not yet compile-validated by GitHub Actions because the current runs fail before runner allocation. Treat it as WIP until CI/local validation executes successfully.

### P0 — rig state is only partially connected to renderer
main still has disconnected Flutter RigMode/UI state. Active PR #17 now has the native half of the path:
native FK Euler -> named skeleton joint -> rest-relative local transform -> global transforms -> joint palette -> redraw.

The missing production link is Flutter `NativeRigController`/FRB-generated API wiring. Undo/redo can expose the authoritative native pose through `pose_snapshot()`, but Flutter does not yet resync/apply that snapshot automatically.

### P1 — PR #17 is WIP, not production
PR #17 now contains NativeRigSession, the preload scope fix, rest-pose GPU skinning, native FK palette updates and rig pose snapshots.
The latest observed workflow is run `37644775789` (#335). All five jobs fail before a runner is assigned: `runner_id: 0`, `steps: []`. This is currently an infrastructure/account runner-allocation blocker rather than evidence that Rust/Flutter compilation failed. Merge only after a real runner executes all jobs successfully.

### P1 — FBX is not decoded
The current native scene path explicitly reports needs_fbx_decoder. GLB/glTF is the working native import route. Do not claim FBX support until a decoder/conversion path is implemented and tested.

### P1 — mobile native texture presentation is incomplete
The repository has explicit native Flutter texture backends/CI for Windows, Linux and macOS. Android/iOS native texture presentation is still a separate milestone.

### P1 — picking/gizmos are not end-to-end
The architecture calls for picking and rig gizmos, but there is not yet a complete renderer-backed bone selection + FK rotation gizmo + IK handle pipeline.

## PR #17 content

The PR has expanded beyond the original three files. Current important changes include:
- CI workflow diagnostics/setup changes.
- app/lib/main.dart preload scope fix.
- app/rust/src/api/rig.rs NativeRigSession + authoritative pose snapshot.
- app/rust/src/api/builder.rs native FK scene-application/reset methods.
- builder_render skeleton_pose, gpu_scene, pipeline, viewport and mesh shader skinning changes.

NativeRigSession provides:
- BridgeRigMode: None / Ik / Fk
- selected bone
- hand open state
- begin/update/commit/cancel gesture
- FK Euler state by bone
- IK target state by effector/bone key
- undo/redo
- PoseState export

Important: NativeRigSession is still the state/history authority. GPU skinning and a native FK deformation path now exist in the same PR, but Flutter has not yet connected rig gestures/undo/redo to that path, and IK still outputs points rather than joint rotations.

## Next implementation order

1. Unblock executable CI for PR #17.
   - GitHub currently creates jobs but assigns no runner (`runner_id: 0`, zero steps).
   - Once runner allocation works, run Rust workspace tests, FRB codegen, Flutter analyze/tests and desktop builds.
   - Fix any real compile/test errors revealed by those runs.
   - Merge only after green.

2. Finish making NativeRigSession the rig source of truth in Flutter.
   - Generate FRB Dart API for api/rig.rs.
   - Add NativeRigController in Flutter.
   - Remove duplicated/divergent local rig state where possible.
   - Wire IK/FK/Open/Close and undo/redo.
   - During pose gesture call workspace.beginPoseGesture(); commit/cancel must unlock navigation.

3. Validate the implemented rest-pose WGPU skinning.
   - The skeleton pose, palette buffer, bind group, shader blending and numerical tests are now in PR #17.
   - Validate with a known tiny skinned GLB once executable CI/local Rust tooling is available.
   - Confirm rest pose renders identically and normal transformation is acceptable for the rig's rigid joint transforms.

4. Finish FK end-to-end in Flutter.
   - Native bone-name -> joint-index -> rest-relative Euler delta -> palette -> redraw exists.
   - Generate FRB Dart bindings.
   - Add NativeRigController and connect selected-bone/gizmo gestures.
   - On undo/redo, use NativeRigSession pose_snapshot() to reset/reapply viewport pose.
   - Coalesce drag updates and commit one history entry on pointer release.

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

## Continuation update — 2026-10-08

- Flutter now has a concrete desktop FK editing path instead of mode-only buttons.
- The rig panel reads real joint names from the loaded base-character NativeViewport scene and refreshes when that scene finishes loading.
- FK bone selection is authoritative through NativeRigSession.
- X/Y/Z FK sliders send coalesced edits through NativeRigController to both Rust history and the WGPU joint-palette path.
- Slider start locks viewport navigation and begins a transient rig gesture; release commits one history step and unlocks navigation; cancel restores the authoritative snapshot and unlocks navigation.
- NativeRigController serializes gesture start behind any pending FK flush to avoid cross-gesture races.
- This is a testable intermediate control surface; final 3D FK gizmo/picking is still pending.
- Mobile still exposes the compact IK/FK rail but does not yet have the bone editor/gizmo.
- IK still needs solved-point -> real joint-rotation conversion before viewport controls should be exposed.

Next exact step: validate this branch with executable CI/local Flutter+Rust tooling, then implement renderer-backed IK joint rotations and reuse the same palette update path. Do not add a second Flutter pose model.

## Continuation update — 2026-10-08 (IK native path)

Completed on active PR #17:
- Fixed a unit-space rig bug in GLB/glTF import: mesh positions were scaled by meters_per_unit while skeleton local translations and inverse-bind translations were not. Skeleton and inverse-bind translations now use the same uniform scene-unit scale, with a regression test.
- Added SkeletonPose joint world-position queries and a two-bone solution application path.
- Added robust direction-to-direction rotation math, affine parent inverse handling, hierarchy validation and tests that prove upper/lower joints aim at solved mid/end points.
- GpuScene and ViewportRenderer can now apply a two-bone solution and upload only the joint palette.
- NativeViewportSession now exposes set_scene_two_bone_ik(): scene + upper/lower/end + target/pole -> builder_core two-bone solve -> skeleton rotations -> WGPU palette -> redraw.
- NativeRigSession now stores complete IK commands (effector, upper, lower, end, target, pole) so Cancel/Undo/Redo can faithfully reconstruct IK.
- NativeViewportController exposes the native IK bridge.
- NativeRigController now coalesces IK updates, serializes them with gesture lifecycle, and syncViewport() replays both FK and IK from the authoritative Rust snapshot.
- Fixed a race where Undo/Redo waited for pending FK work but not pending IK work.

Still pending:
- executable CI/local compile validation (GitHub-hosted runner allocation remains the known external blocker until a new run actually executes steps),
- Rig V3 metadata -> explicit effector chain binding in Flutter/native UI,
- viewport IK handles/picking and mobile manipulation,
- constraints/hinge-axis enforcement from Rig V3 metadata,
- hand open/close connection to actual finger bones or morph targets.

The solver itself is no longer the main IK gap. The next product-facing milestone is chain binding + interactive IK controls/picking on top of this native path.

## Continuation update — 2026-10-08 (interactive IK/FK UI)

- Added Rig V3 chain resolver in Flutter. It prefers authored freshstl_mixamo_rig_v3 metadata from Builder config/base-character metadata and falls back to standard Mixamo names only when authored data is absent.
- Rig V3 semantic chain names are mapped through bones[].source_name/sourceName so custom source joint names work.
- Added tests for authored chains, semantic->source mapping, four standard Mixamo fallback chains and incomplete-chain rejection.
- Native viewport can now query current world position for any loaded joint.
- Desktop IK editor now selects a resolved effector and manipulates X/Y/Z target offsets around the current hand/foot position. Range is based on current two-bone reach.
- Pole point is derived from the Rig V3 pole direction and current chain reach.
- IK slider gestures use the same NativeRigSession transient history, navigation lock, coalescing, WGPU palette update and one-undo-entry-on-release rules as FK.
- Mobile IK/FK rail now opens a bottom-sheet editor backed by the same native controllers; mobile buttons are no longer mode-only toggles.
- Closing a mobile editor during an active pose gesture cancels/resyncs the authoritative native pose.

Remaining high-priority work: executable CI validation, true viewport picking/3D gizmos/IK handles, Rig V3 hinge/primary-axis constraints, and real hand/finger deformation.

## Continuation update — 2026-10-08 (viewport rig interaction)

Completed on active PR #17:
- Native viewport now projects every skeleton joint from world space into current camera/viewport screen coordinates.
- Flutter caches projected joint handles and refreshes them after scene load, resize, orbit, zoom, view changes, FK updates, IK updates and pose reset.
- FK mode now renders real joint picking handles over the native texture. Tapping a handle selects the authoritative NativeRigSession bone.
- Selected FK bones now expose direct X/Y/Z rotation gizmo handles in the viewport. Dragging an axis locks navigation, updates native FK/WGPU skinning and commits one history step on release.
- IK mode now renders only resolved hand/foot effector handles from Rig V3/Mixamo chain bindings.
- NativeRigSession now stores selected_effector as authoritative state; viewport handle selection and the IK editor stay synchronized.
- Added camera screen-drag -> world-space delta conversion using the same FOV/view basis as rendering.
- IK effector handles can now be dragged directly in the viewport. Mouse/touch deltas are converted in Rust to camera-plane world deltas, then sent through the existing NativeRigController -> two-bone IK -> skeleton rotations -> WGPU palette path.
- IK drag input is coalesced, preserves fast early movement while joint context is loading, locks navigation, and commit is serialized after beginGesture plus all pending drag updates.
- FK gizmo start/end is also serialized so commit cannot race beginGesture.

Still pending:
- executable CI/local validation; latest GitHub runs still fail jobs before repository steps execute,
- renderer-backed bone/handle depth occlusion rather than overlay-only visibility,
- more Blender-like circular rotation rings instead of compact axis handles,
- Rig V3 hinge/primary-axis/limit enforcement,
- hand/finger deformation,
- Android/iOS native texture backends.
