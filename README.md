# Fresh Builder Native

Cross-platform FreshSTL Builder client built with **Flutter + Rust**.

Targets:
- Windows
- macOS
- Linux
- Android
- iOS / iPadOS

## Architecture

- `app/` — Flutter UI and responsive interaction shell.
- `rust/` — platform-neutral Builder core.
- `docs/` — architecture and contracts.
- `scripts/` — local bootstrap scripts for generated Flutter platform runners.

The native Builder is being designed to remain compatible with FreshSTL Builder designs and the FreshSTL Rig Profile V3 contract.

## Bootstrap

After cloning, generate Flutter's platform runners:

```bash
cd app
flutter create --platforms=android,ios,windows,macos,linux .
flutter pub get
flutter run
```

Rust core:

```bash
cd rust
cargo test --workspace
```

> Initial bootstrap. The Flutter ↔ Rust FFI/rendering layer is added incrementally so UI, rig math, serialization, and rendering remain independently testable.
