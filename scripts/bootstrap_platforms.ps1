$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $Root "app")

flutter create --project-name fresh_builder --org com.freshstl --platforms=android,ios,windows,macos,linux .
flutter pub get

Write-Host "Fresh Builder platform runners generated."
