# Reload PATH to pick up C:\flutter\bin
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "=== Flutter version ==="
flutter --version

Write-Host "`n=== Running flutter pub get ==="
Set-Location "E:\projects\FixingNation\flutter_app"
flutter pub get

Write-Host "`n=== Flutter doctor (summary) ==="
flutter doctor
