# Code Audit — 2026-10-07

## Scope
Audit of Fresh_builder native Flutter/Rust/WGPU architecture at main 9ba6299 plus unmerged PR #17. Continuation reviewed through PR branch head 40c917e268e27de9dabc001afa81cde25dc2ab33.

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
| Rig edit session | WIP in PR #17 | native history + authoritative pose snapshot; Flutter controller still pending |
| GPU skinning | Implemented in PR, unvalidated | retained skeleton + palette storage buffer + 4-weight WGSL skinning; CI runner never starts |
| FK visual deformation | Partial in PR | native bone-name -> rest-relative Euler -> palette -> redraw path exists; Flutter gizmo/controller not wired |
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
3. main still discards useful skeleton detail after upload, but PR #17 now retains SkeletonPose and the GPU joint palette.
4. main's shader still ignores joints/weights; PR #17 now applies four-weight position/normal skinning.
5. A CPU readback texture path is correctness-first and can become a performance bottleneck at high resolution/frame rate; zero-copy platform surfaces are a later optimization, not a blocker for rig correctness.
6. CI for PR #17 still fails across all jobs before any step executes. Latest run #335 (37644775789) reports runner_id 0 for every job, so no compile/test result exists yet. Do not merge blindly.
7. README/architecture text is stale in places: it still describes viewport/camera as a next milestone even though desktop viewport rendering now exists.

## Renderer gap in concrete terms

Audited main still follows:
RenderScene.skeleton -> upload_scene() -> GpuScene { meshes, joint_count }
mesh.wgsl -> camera * original vertex position

Active PR #17 now follows:
RenderScene.skeleton
-> retained SkeletonPose/rest locals
-> current local pose
-> global joint matrices
-> skin matrices = global_current * inverse_bind
-> GPU storage-buffer joint palette
-> four-weight vertex skinning in WGSL
-> camera transform

Native FK can now update a named joint using a rest-relative Euler delta and redraw by uploading the palette only. The remaining end-to-end gap is Flutter/FRB controller wiring plus IK conversion from solved points to joint rotations.

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
- DONE in PR: rest palette produces identity deformation.
- DONE in PR: parent FK rotation moves child global transform.
- DONE in PR: four-weight skin blend is numerically stable.
- DONE in PR: zero total weight falls back safely.
- DONE in PR: invalid joint index is rejected during scene validation.
- DONE in PR: rest-relative FK delta preserves the joint's bind translation.
- DONE in PR: transient FK/IK gesture creates one undo entry.
- DONE in PR: pose snapshot tracks FK undo/redo state.
- NEXT: IK target -> joint rotations preserves segment lengths and axes.

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

The workflow was updated to remove third-party setup actions and finally even `actions/checkout`, using direct git/rustup/Flutter setup instead. This ruled out those Actions as the common cause.

Latest observed PR run: `37644775789` (#335), head `40c917e268e27de9dabc001afa81cde25dc2ab33`.

Observed for all five jobs:
- conclusion: failure
- `runner_id: 0`
- `steps: []`

Jobs affected:
- native-core
- flutter-bridge
- windows-texture
- linux-texture
- macos-texture

This means no GitHub-hosted runner was assigned and no repository command executed. The connector does not expose the run annotation text, so the exact account/policy reason is not proven here. Treat CI runner allocation as an external blocker; do not interpret these failures as Rust/Flutter compile failures.

## Continuation implementation log

Active PR #17 now includes:
- skeleton hierarchy/current-pose math in `builder_render::skeleton_pose`;
- rest/current skin palette generation;
- GPU palette storage buffer + per-scene bind group;
- WGSL four-joint weighted skinning;
- native palette-only FK updates and pose reset;
- authoritative rig pose snapshots for undo/redo resync;
- wgpu 30.0.1 pipeline-layout compatibility fix;
- CI workflow changes intended to expose real code failures once a runner is allocated.

The branch remains unmerged and must not be called production-ready until executable CI/local validation passes.

## Immediate next task

1. Restore executable GitHub-hosted runner allocation (or run the validation commands in another trusted environment) so PR #17 can receive a real compile/test result.
2. Run FRB codegen and add the Flutter NativeRigController.
3. Wire Flutter FK gesture updates to NativeRigSession + NativeViewportSession.set_scene_fk_rotation(), using pose_snapshot() to resync after undo/redo.
4. Validate the implemented skinning with a known tiny skinned GLB before adding polished gizmos.
5. Then convert two-bone IK results into real upper/lower joint rotations and feed the same palette path.

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

## Continuation update — 2026-10-08 (Rig V3 constraints + real hands)

Completed on active PR #17:
- Added Rig V3 bone constraint resolver for primary_axis and hinge_axis metadata.
- Hinge bones are reduced to the dominant local X/Y/Z axis for current Euler-based FK editing. Free bones keep X/Y/Z.
- Desktop FK sliders, mobile FK editor and viewport FK gizmo now hide disallowed axes.
- _updateFkAxis() also guards constraints so stale/legacy UI events cannot rotate a hinge bone on a forbidden axis.
- FK gizmo now renders Blender-like rotation-ring visuals around the selected joint while retaining the compact axis hit targets.
- Added tests for Rig V3 hinge-axis resolution.
- Implemented native Mixamo finger open/close deformation in SkeletonPose. Finger joints are detected by LeftHand/RightHand + Thumb/Index/Middle/Ring/Pinky naming.
- Hand curl updates all detected finger joints first, then performs a single GPU joint-palette upload.
- Added a Rust regression test proving hand close changes only finger joints and open restores their rest transforms.
- NativeViewportSession/Flutter viewport now expose set_scene_hand_open / setSceneHandOpen.
- Rig resync after Cancel/Undo/Redo reapplies snapshot.hand_open after FK and IK.
- Desktop and mobile hand buttons now use one page-level command that updates both NativeRigSession state and real renderer deformation.
- UI status reports the number of finger joints affected, or explicitly reports when no Mixamo finger joints were found.

Known constraint boundary:
- Rig V3 currently provides primary_axis/hinge_axis but no explicit angular min/max limits in the current core schema. No arbitrary angle limits were invented. A future schema field should carry authored limits before native hard-clamping is added.
- Finger fallback is explicitly Mixamo-name based until uploader/Rig V3 exports dedicated finger metadata.

## Continuation update — 2026-10-08 (optional FK rotation limits)

- Rig V3 Flutter resolver now parses optional per-axis rotation_limits / rotationLimits / limits metadata.
- Each bone constraint can clamp FK values per X/Y/Z without changing behavior for older rigs that omit limits.
- Desktop/mobile FK sliders use authored min/max when present.
- Viewport FK gizmo clamps rotation to authored limits before sending updates to NativeRigController/WGPU.
- The page-level FK update path also clamps, so stale UI paths cannot bypass authored limits.
- Added tests for optional FK rotation-limit parsing and clamping.

Uploader work still needed: emit rotation_limits metadata from Blender when the autorig has authored joint limits. Existing V3 files remain compatible and unconstrained when limits are absent.
