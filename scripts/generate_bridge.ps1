$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root "app"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is required"
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Rust/Cargo is required"
}
if (-not (Get-Command flutter_rust_bridge_codegen -ErrorAction SilentlyContinue)) {
  cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
}

Set-Location $App
flutter pub get
flutter_rust_bridge_codegen generate

Write-Host "Fresh Builder Flutter/Rust bindings generated."
