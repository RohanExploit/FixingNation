$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Set-Location "E:\projects\FixingNation\flutter_app"

Write-Host "=== Generating Android platform files ==="
flutter create --platforms android .

Write-Host "`n=== Package name in build.gradle ==="
Get-Content "android\app\build.gradle" | Select-String "applicationId|namespace"
