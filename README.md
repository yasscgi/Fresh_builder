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
- CI definitions for Rust, FRB codegen and Flutter analysis
- Supabase Flutter runtime using the existing FreshSTL Builder schema
- FreshSTL account sign in / sign up / sign out
- accessible Builder product picker backed by existing RLS
- typed loading of Builder config, categories, assets, articulated chains, joints and surface zones
- protected private-download asset URLs through an authenticated Edge Function
- in-memory signed URL cache for model/thumbnail reuse
- RLS-backed saved Builder designs
- publishable-key-only client configuration; no privileged key is shipped in the app

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


## Supabase runtime

The native client connects to the existing FreshSTL Supabase project. It does not create a second Builder schema.

Client credentials are public runtime values and can be overridden at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Access to Builder configuration and assets remains controlled by the existing database RLS policies and `user_has_product_access(product_id)`. Never place a secret/service-role key in the Flutter application.

Protected `private-downloads` files are resolved through the authenticated `builder-asset-url` Edge Function and cached only until shortly before the signed URL expires. See `docs/SUPABASE_NATIVE.md` for the full flow.
