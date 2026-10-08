#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS bootstrap requires macOS." >&2
  exit 2
fi

cd "$APP"
flutter create --project-name fresh_builder --org com.freshstl --platforms=ios .
flutter pub get
if [[ ! -d "hook" && ! -d "rust_builder" ]]; then
  flutter_rust_bridge_codegen integrate --integration-backend native-assets
fi
flutter_rust_bridge_codegen generate

cd "$APP/packages/fresh_builder_viewport_texture"
flutter analyze
flutter test

cd "$APP"
flutter analyze
flutter test
flutter build ios --debug --no-codesign

echo "iOS bootstrap/build completed."
