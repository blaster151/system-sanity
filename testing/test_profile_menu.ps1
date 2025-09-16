# Test script to verify profile menu functionality
# This simulates the profile menu behavior without running the full system-sanity script

# Load the profiles
$profilesPath = "profiles.json"
function Load-Profiles {
  param([string]$Path)
  if (!(Test-Path $Path)) { return @{} }
  try {
    $json = Get-Content $Path -Raw -Encoding UTF8
    return $json | ConvertFrom-Json
  } catch {
    Write-Warning ("Could not parse profiles file: {0}" -f $Path)
    return @{}
  }
}

function Show-ProfileMenu {
  param([hashtable]$Profiles)
  
  if ($Profiles.PSObject.Properties.Name.Count -eq 0) {
    Write-Host "No profiles available. Using default behavior." -ForegroundColor Yellow
    return $null
  }
  
  Write-Host ""
  Write-Host "Available Profiles:" -ForegroundColor Cyan
  Write-Host "==================" -ForegroundColor Cyan
  
  $profileNames = $Profiles.PSObject.Properties.Name | Sort-Object
  $index = 1
  
  foreach ($profileName in $profileNames) {
    $profile = $Profiles.$profileName
    $description = ""
    
    # Generate a brief description based on profile contents
    if ($profile.KillProcesses) {
      $killCount = $profile.KillProcesses.Count
      $description += "Kills $killCount process types"
    }
    if ($profile.StopServicesPre) {
      $serviceCount = $profile.StopServicesPre.Count
      if ($description) { $description += ", " }
      $description += "Stops $serviceCount services"
    }
    if ($profile.LaunchAppsPost) {
      $appCount = $profile.LaunchAppsPost.Count
      if ($description) { $description += ", " }
      $description += "Launches $appCount apps"
    }
    if (-not $description) {
      $description = "Basic profile"
    }
    
    Write-Host ("{0}. {1,-12} - {2}" -f $index, $profileName, $description) -ForegroundColor White
    $index++
  }
  
  Write-Host ""
  Write-Host ("{0}. Skip profile selection (use default junk-kill list)" -f $index) -ForegroundColor Gray
  Write-Host ("{0}. Exit" -f ($index + 1)) -ForegroundColor Red
  Write-Host ""
  
  do {
    try {
      $choice = Read-Host "Select a profile (1-$($index + 1))"
      $choiceNum = [int]$choice
      
      if ($choiceNum -ge 1 -and $choiceNum -le $profileNames.Count) {
        $selectedProfile = $profileNames[$choiceNum - 1]
        Write-Host ("Selected profile: {0}" -f $selectedProfile) -ForegroundColor Green
        return $selectedProfile
      }
      elseif ($choiceNum -eq $index) {
        Write-Host "Using default behavior (no profile)" -ForegroundColor Yellow
        return $null
      }
      elseif ($choiceNum -eq ($index + 1)) {
        Write-Host "Exiting..." -ForegroundColor Red
        exit 0
      }
      else {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
      }
    }
    catch {
      Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
    }
  } while ($true)
}

# Test the menu
$Profiles = Load-Profiles -Path $profilesPath
Write-Host "Testing profile menu functionality..."
Write-Host "Profiles loaded: $($Profiles.PSObject.Properties.Name.Count)"

# Show the menu
$selectedProfile = Show-ProfileMenu -Profiles $Profiles
Write-Host "Final selection: $selectedProfile"