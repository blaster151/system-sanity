# Test script for Enhanced Profile System with Interactive Prompts
# This script tests the new profile-based interactive prompts functionality

# Mock service data for testing
$mockServices = @(
    [PSCustomObject]@{ Name = "WlanSvc"; DisplayName = "WLAN AutoConfig"; Description = "Configures wireless LAN" },
    [PSCustomObject]@{ Name = "AudioSrv"; DisplayName = "Windows Audio"; Description = "Manages audio devices" },
    [PSCustomObject]@{ Name = "BthServ"; DisplayName = "Bluetooth Support Service"; Description = "Manages Bluetooth" },
    [PSCustomObject]@{ Name = "Themes"; DisplayName = "Themes"; Description = "Manages visual themes" },
    [PSCustomObject]@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry"; Description = "Collects telemetry data" },
    [PSCustomObject]@{ Name = "DefragSvc"; DisplayName = "Optimize drives"; Description = "Optimizes disk performance" }
)

# Load the profiles configuration
$profilesPath = ".\profiles.json"
if (Test-Path $profilesPath) {
    $profilesJson = Get-Content $profilesPath -Raw -Encoding UTF8
    $profiles = $profilesJson | ConvertFrom-Json
    Write-Host "Loaded profiles: $($profiles.PSObject.Properties.Name -join ', ')" -ForegroundColor Green
} else {
    Write-Host "profiles.json not found!" -ForegroundColor Red
    exit 1
}

# Include the functions from assess_services.ps1
. .\assess_services.ps1

Write-Host "Testing Enhanced Profile System with Interactive Prompts" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""

# Test 1: Show profile configurations
Write-Host "Test 1: Profile Configurations" -ForegroundColor Yellow
foreach ($profileName in $profiles.PSObject.Properties.Name) {
    $profile = $profiles.$profileName
    Write-Host "Profile: $profileName" -ForegroundColor White
    
    if ($profile.InteractivePrompts) {
        Write-Host "  Interactive Prompts:" -ForegroundColor Cyan
        foreach ($promptKey in $profile.InteractivePrompts.PSObject.Properties.Name) {
            $prompt = $profile.InteractivePrompts.$promptKey
            $status = if ($prompt.enabled) { "enabled" } else { "disabled" }
            Write-Host "    $promptKey: $status - '$($prompt.title)'" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No interactive prompts configured" -ForegroundColor Gray
    }
    Write-Host ""
}

# Test 2: Service tagging
Write-Host "Test 2: Service Tagging" -ForegroundColor Yellow
foreach ($svc in $mockServices) {
    $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
    Write-Host "Service: $($svc.Name) -> Tags: $($tags -join ', ')" -ForegroundColor White
}
Write-Host ""

# Test 3: Test different profiles with mock user preferences
Write-Host "Test 3: Profile-based Opinions" -ForegroundColor Yellow

foreach ($profileName in @("normal", "gaming", "dev")) {
    if ($profiles.$profileName) {
        $profile = $profiles.$profileName
        Write-Host "Testing profile: $profileName" -ForegroundColor White
        
        # Mock user preferences (simulating user saying "yes" to all prompts)
        $mockUserPrefs = @{
            "network" = $true
            "audio" = $true
            "bluetooth" = $false
            "ui" = $true
            "storage-opt" = $false
            "telemetry" = $false
        }
        
        foreach ($svc in $mockServices) {
            $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
            $op = Get-Opinion -tags $tags -userPreferences $mockUserPrefs -profileConfig $profile
            
            $needed = switch ($profileName) {
                "dev" { $op.Dev }
                "gaming" { $op.Gaming }
                default { $op.Normal }
            }
            
            Write-Host "  $($svc.Name): $needed" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

# Test 4: Test profile defaults (no user preferences)
Write-Host "Test 4: Profile Defaults (no user preferences)" -ForegroundColor Yellow

foreach ($profileName in @("normal", "gaming", "dev")) {
    if ($profiles.$profileName) {
        $profile = $profiles.$profileName
        Write-Host "Testing profile: $profileName (defaults only)" -ForegroundColor White
        
        foreach ($svc in $mockServices) {
            $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
            $op = Get-Opinion -tags $tags -userPreferences @{} -profileConfig $profile
            
            $needed = switch ($profileName) {
                "dev" { $op.Dev }
                "gaming" { $op.Gaming }
                default { $op.Normal }
            }
            
            Write-Host "  $($svc.Name): $needed" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

Write-Host "Enhanced Profile System Test completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To use the enhanced functionality:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractivePrompts" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode gaming -InteractivePrompts" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode dev -InteractivePrompts" -ForegroundColor White
Write-Host ""
Write-Host "Through system-sanity.ps1:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile normal -ServiceAssess -ServiceInteractivePrompts" -ForegroundColor White