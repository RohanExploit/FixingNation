# Find puro executable
$puroPaths = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links\puro.exe",
    "$env:LOCALAPPDATA\Programs\puro\puro.exe",
    "$env:ProgramFiles\puro\puro.exe"
)

$puroExe = $null
foreach ($p in $puroPaths) {
    if (Test-Path $p) { $puroExe = $p; break }
}

if (-not $puroExe) {
    # Search common locations
    $found = Get-ChildItem -Path "$env:LOCALAPPDATA" -Filter "puro.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $puroExe = $found.FullName }
}

Write-Host "Puro location: $puroExe"

if ($puroExe) {
    Write-Host "Creating stable Flutter environment..."
    & $puroExe create stable
    Write-Host "Setting stable as default..."
    & $puroExe use stable
    Write-Host "Done. Flutter version:"
    & $puroExe flutter --version
} else {
    Write-Host "Puro not found. Checking PATH..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    & puro create stable
}
