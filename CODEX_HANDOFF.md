# CODEX HANDOFF — Fresh Builder Native

Last updated: 2026-10-08

## Mission
Validate and harden the merged Fresh Builder Native implementation. Do not redesign the architecture unless a failing test proves it is necessary. Fix compile/runtime issues in the smallest layer that owns them.

## Read first
1. `AI_HANDOFF.md`
2. `docs/CODE_AUDIT_2026-10-07.md`
3. This file
4. `app/lib/main.dart`
5. `app/lib/src/workspace/asset_transform_ui.dart`
6. `app/lib/src/workspace/native_viewport_controller.dart`
7. `app/lib/src/workspace/native_rig_controller.dart`
8. `app/rust/src/api/builder.rs`
9. `app/rust/src/api/rig.rs`
10. `rust/crates/builder_render/src/gpu_scene.rs`
11. `rust/crates/builder_render/src/skeleton_pose.rs`
12. `rust/crates/builder_io/src/stl.rs`
13. `rust/crates/builder_io/src/three_mf.rs`
14. `rust/crates/builder_io/src/validation.rs`

## Architecture map

### Flutter UI
- `app/lib/main.dart`: product/session orchestration, cloud asset selection, rig panels, save/restore/export actions.
- `asset_transform_ui.dart`: direct viewport Move/Rotate/Scale gizmo + transform panel.
- `builder_persistence_actions.dart`: shared desktop/mobile Save/Restore/Validate/STL/3MF actions.
- `builder_design_persistence.dart`: Design v5 JSON persistence + export path helpers.
- `native_viewport_surface.dart`: camera pointer/touch input.
- `native_viewport_controller.dart`: persistent native viewport session, scene lifecycle, projection, transforms, texture frame publishing.
- `native_rig_controller.dart`: authoritative Flutter-side rig session orchestration and replay.

### Rust bridge
- `app/rust/src/api/builder.rs`: viewport, scene import, camera, FK/IK render application, print validation, STL/3MF export.
- `app/rust/src/api/rig.rs`: rig state/history, FK/IK command snapshots, hand-open state.

### Rust engine
- `builder_core`: Design v5 model, generic history, Rig V3 semantics, two-bone IK.
- `builder_render`: WGPU renderer, GPU skinning, skeleton pose, per-scene model transform, depth-aware projected picking.
- `builder_io`: GLB/glTF decoding, binary STL, dependency-free 3MF package writer, print validation.

## Data flow
```
Flutter gesture
 -> NativeRigController / NativeViewportController
 -> FRB NativeViewportSession / NativeRigSession
 -> SkeletonPose / GpuScene
 -> joint palette + model transform
 -> WGPU
```

Export flow:
```
Current SkeletonPose palette
 -> CPU skin bake
 -> per-scene model transform bake
 -> merged static RenderScene
 -> validation
 -> STL or 3MF writer
```

## Critical invariants
Do NOT break these while fixing:
1. Asset Move/Rotate/Scale affects only selected asset scene, never IK/FK.
2. Rig pose and asset transform histories are separate.
3. Continuous drag creates one undo entry (commit-on-release).
4. Static meshes are not re-uploaded for pose edits.
5. FK/IK updates upload joint palette only.
6. Asset transforms update one model uniform only.
7. IK/FK camera navigation locks while editing.
8. Depth readback is not performed continuously during live rig drag.
9. Base character scene key stays `role:base_character`.
10. Rig V3 remains backward compatible when optional rotation limits are absent.
11. Protected assets continue using authenticated signed URLs; never ship Supabase service-role credentials.
12. Design format is `fresh_builder_design`, version 5.

## Validation order
Run in this exact order. Stop and fix the first real code error before continuing.

### 1. Rust workspace
```bash
cd rust
cargo fmt --all -- --check
cargo test --workspace
```

### 2. App Rust bridge
```bash
cd app/rust
cargo fmt --all -- --check
cargo test
```

### 3. Regenerate flutter_rust_bridge
From `app/`:
```bash
flutter_rust_bridge_codegen generate
```
If generated method names differ from handwritten Dart calls, trust generated FRB naming and update Dart callers. Do not rename Rust APIs just to match guesses.

### 4. Flutter static checks
```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

### 5. Desktop builds
Windows:
```powershell
flutter build windows --debug
```
Linux:
```bash
flutter build linux --debug
```
macOS:
```bash
flutter build macos --debug
```

### 6. Manual smoke test
- open product
- base character loads
- select one asset
- Move/Rotate/Scale via sliders
- Move/Rotate/Scale via viewport gizmo
- asset transform Undo/Redo
- IK hand/foot drag
- FK bone select + rotation
- Open/Close hands
- rig Undo/Redo/Cancel
- save Design v5
- alter scene
- restore Design v5
- Validate Print
- Export STL
- Export 3MF
- open STL/3MF in slicer and compare pose/asset placement against viewport

## Highest-probability compile/runtime risks to check first
1. FRB generated Dart signatures for:
   - `validateCurrentPrint`
   - `exportCurrent3mf`
   - `worldPointScreenPosition`
   - `screenDragWorldDeltaAt`
   - `BridgeSceneTransform`
2. WGPU 30 texture-to-buffer depth readback API exact types.
3. Flutter `Slider.value` values must be `double`, not `num`.
4. Dart enum name serialization in Design v5.
5. Design restore ordering: scenes must load before transforms and rig replay.
6. 3MF ZIP package compatibility with Bambu Studio/PrusaSlicer/OrcaSlicer.
7. STL and 3MF now both bake engine meters -> millimeters for slicer-facing coordinates.
8. Validate Print reports final X/Y/Z dimensions in millimeters; verify a known 100 mm model reports 100 mm before release.
9. Print validation is topology validation, not boolean union/repair.
10. Multiple overlapping meshes are exported as separate shells; this is intentional until a robust union/remesh stage exists.
11. FBX remains `needs_fbx_decoder`; GLB/glTF is the working native import route.
12. Android/iOS native texture backend is not complete.

## Print units
The renderer normalizes imported data into engine meters. Export is now explicit:
- STL: engine meters are multiplied by 1000 before writing coordinates.
- 3MF: model unit is `millimeter` and engine meters are multiplied by 1000.
- Validate Print reports bounding dimensions in millimeters.

Regression tests cover 0.1 m -> 100 mm. Still verify one known-size real asset in Bambu/Orca/Prusa before release.

## Design v5 restore contract
Restore order must remain:
1. verify product id
2. reset rig and viewport scenes
3. load asset files
4. insert scenes under saved scene keys
5. apply scene transforms
6. replay FK
7. replay IK
8. apply hand state
9. restore selected bone/effector/mode
10. refresh depth-aware handles

## Print validation meaning
`watertight=true` currently requires:
- no invalid indices
- no degenerate triangles
- no boundary edges
- no non-manifold edges

This does NOT prove:
- shells do not intersect
- normals are consistently oriented
- minimum wall thickness
- boolean union was performed

## CI caveat
GitHub Actions has repeatedly returned jobs with `steps=null` and runner failures before repository steps. Treat that as infrastructure failure, not proof of code correctness. Local Codex validation is required.

## Fast fix policy for Codex
- Fix compile errors first.
- Then failing unit tests.
- Then runtime smoke failures.
- Do not perform broad refactors during first validation pass.
- Keep each fix isolated and commit with a descriptive message.
- After each fix rerun the narrow failing command, then the full stage.
- Update `AI_HANDOFF.md` and `docs/CODE_AUDIT_2026-10-07.md` after a meaningful milestone.

## Definition of done
- Rust workspace tests pass.
- app/rust tests pass.
- FRB generation is clean.
- flutter analyze has zero errors.
- flutter tests pass.
- Windows build passes.
- one known-size asset exports at correct physical size.
- posed character STL matches viewport.
- 3MF opens in at least one slicer.
- save/restore reproduces same assets, transforms and pose.
- IK/FK/hand controls do not rotate camera while dragging.


## Mobile texture status
- Android viewport texture plugin now exists under `app/packages/fresh_builder_viewport_texture/android`.
- It uses Java + JNI/C++ to resolve the Rust frame bridge and posts RGBA frames to a Flutter SurfaceTexture.
- iOS viewport texture plugin now exists under `app/packages/fresh_builder_viewport_texture/ios`.
- It uses FlutterTexture + CVPixelBuffer and resolves the Rust C ABI from the process/framework.
- Bootstrap scripts:
  - `scripts/bootstrap_android.ps1`
  - `scripts/bootstrap_android.sh`
  - `scripts/bootstrap_ios.sh`
- CI includes Android and iOS mobile jobs, but hosted-runner failures may still block execution before steps.


## Cloud Design v5 status
- Native Save Design now writes the same Design v5 snapshot locally and, when authenticated, inserts it into Supabase `saved_builder_designs` using the existing RLS-protected schema from freshstl-main.
- Native Restore checks the latest authenticated cloud row only when its design payload has `format=fresh_builder_design` and `version=5`; otherwise it falls back to the local snapshot.
- Existing web Builder V2 saved rows remain untouched and are not misinterpreted as Native Design v5.


## Post-merge autosave and export preflight
- Local Design v5 autosave is debounced (900 ms) after rig/hand changes, asset selection and committed asset transforms. Autosave failures are best-effort and non-fatal; explicit Save Design still reports errors.
- Explicit Save Design stores local + authenticated Supabase `saved_builder_designs` copy.
- STL/3MF export runs print validation first and blocks invalid triangle indices or empty geometry. Non-watertight topology is exported with clear warnings instead of silently claiming a clean model.
