# Test script for Issue 11 - Interactive "Needed for normal" functionality
# This script tests the new interactive prompts for additional services

# Mock service data for testing
$mockServices = @(
    [PSCustomObject]@{ Name = "WlanSvc"; DisplayName = "WLAN AutoConfig"; Description = "Configures wireless LAN" },
    [PSCustomObject]@{ Name = "AudioSrv"; DisplayName = "Windows Audio"; Description = "Manages audio devices" },
    [PSCustomObject]@{ Name = "BthServ"; DisplayName = "Bluetooth Support Service"; Description = "Manages Bluetooth" },
    [PSCustomObject]@{ Name = "Themes"; DisplayName = "Themes"; Description = "Manages visual themes" },
    [PSCustomObject]@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry"; Description = "Collects telemetry data" }
)

# Include the functions from assess_services.ps1
. .\assess_services.ps1

Write-Host "Testing Issue 11 - Interactive 'Needed for normal' functionality" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""

# Test 1: Get service tags
Write-Host "Test 1: Service Tagging" -ForegroundColor Yellow
foreach ($svc in $mockServices) {
    $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
    Write-Host "Service: $($svc.Name) -> Tags: $($tags -join ', ')" -ForegroundColor White
}
Write-Host ""

# Test 2: Get opinions without user preferences
Write-Host "Test 2: Default Opinions (no user preferences)" -ForegroundColor Yellow
foreach ($svc in $mockServices) {
    $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
    $op = Get-Opinion -tags $tags
    Write-Host "Service: $($svc.Name) -> Normal: $($op.Normal)" -ForegroundColor White
}
Write-Host ""

# Test 3: Get opinions with user preferences
Write-Host "Test 3: Opinions with User Preferences" -ForegroundColor Yellow
$userPrefs = @{
    "network" = $true
    "audio" = $true
    "bluetooth" = $false
    "ui" = $true
    "telemetry" = $false
}

foreach ($svc in $mockServices) {
    $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
    $op = Get-Opinion -tags $tags -userPreferences $userPrefs
    Write-Host "Service: $($svc.Name) -> Normal: $($op.Normal)" -ForegroundColor White
}
Write-Host ""

Write-Host "Test completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To use the new functionality:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractiveNormal" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile normal -ServiceAssess -ServiceInteractiveNormal" -ForegroundColor White