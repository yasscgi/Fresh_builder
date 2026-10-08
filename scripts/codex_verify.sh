#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Fresh Builder Codex verify =="
cd "$ROOT/rust"
cargo fmt --all -- --check
cargo test --workspace

cd "$ROOT/app/rust"
cargo fmt --all -- --check
cargo test

cd "$ROOT/app"
if [[ ! -d "hook" && ! -d "rust_builder" ]]; then
  flutter_rust_bridge_codegen integrate --integration-backend native-assets
fi
flutter_rust_bridge_codegen generate
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

case "$(uname -s)" in
  Linux*) flutter build linux --debug ;;
  Darwin*) flutter build macos --debug ;;
esac

echo "Verification completed."
