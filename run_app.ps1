$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Set-Location "E:\projects\FixingNation\flutter_app"

Write-Host "=== Connected devices ==="
flutter devices

Write-Host "`n=== Starting build and run ==="
flutter run
