#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"

command -v flutter >/dev/null 2>&1 || { echo "Flutter is required"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "Rust/Cargo is required"; exit 1; }

if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
fi

cd "$APP_DIR"
flutter pub get
flutter_rust_bridge_codegen generate

echo "Fresh Builder Flutter/Rust bindings generated."
