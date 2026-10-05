#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/app"

flutter create --project-name fresh_builder --org com.freshstl --platforms=android,ios,windows,macos,linux .
flutter pub get

echo "Fresh Builder platform runners generated."
