$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Set-Location "E:\projects\FixingNation\flutter_app"
flutter analyze --no-fatal-infos 2>&1
