Write-Host "LightScope Installation Check" -ForegroundColor Green

$path = "$env:LOCALAPPDATA\LightScope"
Write-Host "Installation path: $path"

if (Test-Path $path) {
    Write-Host "Installation found!" -ForegroundColor Green
} else {
    Write-Host "Installation not found" -ForegroundColor Red
}

Write-Host "Python processes:"
Get-Process python* -ErrorAction SilentlyContinue 