# Fresh Builder Native

Cross-platform FreshSTL Builder client built with **Flutter + Rust**.

Targets:
- Windows
- macOS
- Linux
- Android
- iOS / iPadOS

## Architecture

- `app/` — Flutter UI and Flutter-facing Rust bridge crate.
- `rust/crates/builder_core` — Builder state, Rig V3, history and IK logic.
- `rust/crates/builder_render` — WGPU rendering/runtime layer.
- `docs/` — architecture and contracts.
- `scripts/` — platform and bridge bootstrap scripts.

The native Builder keeps the FreshSTL Rig Profile V3 contract and is designed to share Builder designs with the web Builder.

## Current native foundation

Implemented:
- responsive Flutter desktop/mobile shell
- light/dark Builder UI
- renderer-independent Builder state
- transient undo/redo model
- FreshSTL Rig Profile V3 types
- two-bone IK solver
- flutter_rust_bridge 2.13 source contract
- WGPU 30 adapter probing
- Supabase Auth + RLS-backed FreshSTL Builder cloud data
- protected Builder asset signed-URL Edge Function
- CI definitions for Rust, FRB codegen and Flutter analysis

Next rendering milestone:
- native WGPU viewport surface/texture transport
- camera/navigation
- picking and gizmos
- live Rig V3 IK/FK

## Bootstrap

After cloning, generate Flutter's platform runners:

```bash
cd app
flutter create --platforms=android,ios,windows,macos,linux .
flutter pub get
```

Generate Dart/Rust bridge bindings:

macOS/Linux:

```bash
bash scripts/generate_bridge.sh
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_bridge.ps1
```

Run reusable Rust core tests:

```bash
cd rust
cargo test --workspace
```

The Flutter-facing Rust crate lives at `app/rust` and depends on the reusable engine crates rather than duplicating their logic.


## FreshSTL cloud

Cloud integration reuses the existing FreshSTL Supabase project. Run with a publishable key:

```bash
cd app
flutter run --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```

Do not use a service-role or secret key in the native app. See `docs/SUPABASE_NATIVE.md` for the access and protected-asset flow.
