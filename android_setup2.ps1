$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "=== Setting correct Android SDK path ==="
flutter config --android-sdk "R:\andriod_components"

Write-Host "`n=== Flutter doctor ==="
flutter doctor
