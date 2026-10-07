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
