#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"

cd "$APP"
flutter create --project-name fresh_builder --org com.freshstl --platforms=android .
flutter pub get
flutter_rust_bridge_codegen generate

cd "$APP/packages/fresh_builder_viewport_texture"
flutter analyze
flutter test

cd "$APP"
flutter analyze
flutter test
flutter build apk --debug

echo "Android bootstrap/build completed."
