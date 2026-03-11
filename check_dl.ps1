$zip = "$env:TEMP\flutter_windows.zip"
if (Test-Path $zip) {
    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host "Downloaded: $mb MB"
} else {
    Write-Host "Zip not found yet"
}
