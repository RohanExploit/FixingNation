$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "=== Step 1: Configuring Android SDK path ==="
flutter config --android-sdk "R:\android_components"

Write-Host "`n=== Step 2: Flutter doctor (pre-license check) ==="
flutter doctor
