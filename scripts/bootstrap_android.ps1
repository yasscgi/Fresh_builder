$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot/.."
$app = Join-Path $root "app"

Push-Location $app
try {
  flutter create --project-name fresh_builder --org com.freshstl --platforms=android .
  flutter pub get
  if (-not (Test-Path "hook") -and -not (Test-Path "rust_builder")) {
  flutter_rust_bridge_codegen integrate --integration-backend native-assets
}
flutter_rust_bridge_codegen generate
  Push-Location "packages/fresh_builder_viewport_texture"
  try {
    flutter analyze
    flutter test
  } finally {
    Pop-Location
  }
  flutter analyze
  flutter test
  flutter build apk --debug
} finally {
  Pop-Location
}
Write-Host "Android bootstrap/build completed."
