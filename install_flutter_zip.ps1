# Clean up failed puro environment first
$puro = "C:\Users\ACER\AppData\Local\Microsoft\WinGet\Links\puro.exe"
if (Test-Path $puro) {
    Write-Host "Removing failed puro environment..."
    & $puro rm stable --force 2>$null
}

# Download Flutter stable zip directly (no git required)
$flutterDir  = "C:\flutter"
$zipPath     = "$env:TEMP\flutter_windows.zip"
$releasesUrl = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"

# Get latest stable version download URL
Write-Host "Fetching latest stable release info..."
try {
    $releases   = Invoke-RestMethod -Uri $releasesUrl -TimeoutSec 30
    $latestHash = $releases.current_release.stable
    $release    = $releases.releases | Where-Object { $_.hash -eq $latestHash } | Select-Object -First 1
    $dlUrl      = "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
    Write-Host "Downloading Flutter $($release.version) from $dlUrl"
} catch {
    # Fallback to a known stable URL
    Write-Host "Could not fetch release info, using known stable URL..."
    $dlUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.27.4-stable.zip"
}

# Download with progress
Write-Host "Downloading Flutter SDK (this may take a few minutes)..."
$ProgressPreference = 'SilentlyContinue'  # Speeds up Invoke-WebRequest significantly
Invoke-WebRequest -Uri $dlUrl -OutFile $zipPath -TimeoutSec 600
Write-Host "Download complete. Extracting to C:\flutter..."

# Remove old flutter dir if it exists
if (Test-Path $flutterDir) { Remove-Item $flutterDir -Recurse -Force }

# Extract
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, "C:\")

Write-Host "Extraction done."

# Add to user PATH if not already there
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$flutterBin = "C:\flutter\bin"
if ($userPath -notlike "*$flutterBin*") {
    [System.Environment]::SetEnvironmentVariable(
        "Path",
        "$userPath;$flutterBin",
        "User"
    )
    Write-Host "Added C:\flutter\bin to user PATH."
}

# Quick verify
$flutterExe = "C:\flutter\bin\flutter.bat"
if (Test-Path $flutterExe) {
    Write-Host "Flutter installed successfully!"
    & $flutterExe --version
} else {
    Write-Host "ERROR: flutter.bat not found at expected location."
    Get-ChildItem "C:\flutter\bin" | Select-Object Name | Head 10
}

# Cleanup zip
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Write-Host "Done!"
