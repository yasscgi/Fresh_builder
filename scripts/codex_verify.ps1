$ErrorActionPreference = "Stop"
Write-Host "== Fresh Builder Codex verify =="

Push-Location "$PSScriptRoot/../rust"
cargo fmt --all -- --check
cargo test --workspace
Pop-Location

Push-Location "$PSScriptRoot/../app/rust"
cargo fmt --all -- --check
cargo test
Pop-Location

Push-Location "$PSScriptRoot/../app"
flutter_rust_bridge_codegen generate
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --debug
Pop-Location

Write-Host "Verification completed."
