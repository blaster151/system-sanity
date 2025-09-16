# system-sanity.ps1
# Triage + perf snapshot (typeperf) + service maps + CSV transform + optional profiles
# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1
#     (will show interactive profile menu at startup)
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -DurationSecs 60
#     (will show interactive profile menu at startup)
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -DurationSecs 90 -Profile gaming
#     (bypasses menu, uses gaming profile directly)
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile dev -RestoreAfter
#     (bypasses menu, uses dev profile directly)
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -ListProfiles
#     (lists available profiles and exits)

param(
  [int]$DurationSecs = 120,
  [int]$IntervalSecs = 5,
  [string]$Profile,           # e.g., "gaming", "dev", "normal" (if not specified, interactive menu will be shown)
  [switch]$RestoreAfter,      # if present, try to restore services/apps defined by the profile after capture
  [switch]$ListProfiles,      # list available profiles and exit
  [switch]$DryRun,            # plan-only; do NOT kill/stop/start/launch
  [switch]$ForceChrome,       # suppress interactive confirm for Chrome kills
  [switch]$RestoreChrome,     # explicitly relaunch Chrome with --restore-last-session
  [switch]$Capture,           # only collect perf data if explicitly set
  [switch]$ServiceAssess,     # run assess_services.ps1 up front
  [switch]$ServiceApply,      # actually change startup type/stop services
  [switch]$ServicePromptEach  # prompt per service when applying
)

$ErrorActionPreference = "Stop"

# ----- Paths -----
$projectRoot = Split-Path -Parent $PSCommandPath
$outDir      = Join-Path $projectRoot "out"
$csvInput    = Join-Path $outDir "typeperf_SD.csv"
$profilesPath = Join-Path $projectRoot "profiles.json"
New-Item -Type Directory -Path $outDir -Force | Out-Null

# ----- Helpers -----
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

function Kill-ProcessesByPatterns {
  param([string[]]$Patterns)
  if (-not $Patterns -or $Patterns.Count -eq 0) { return @() }
$killed = @()
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $n = $_.Name
    $Patterns | ForEach-Object { if ($n -like $_) { $true } }
} | ForEach-Object {
    $info = [PSCustomObject]@{
        Name  = $_.Name
        PID   = $_.Id
        RAMMB = "{0:N2}" -f ($_.WorkingSet64 / 1MB)
    }
    try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        $killed += $info
    } catch {
        Write-Warning ("Could not kill {0} ({1}) : {2}" -f $_.Name, $_.Id, $_.Exception.Message)
    }
}
  return $killed
}

function Stop-ServicesInOrder {
  param([string[]]$Services)
  if (-not $Services) { return }
  foreach ($svc in $Services) {
    try {
      $s = Get-Service -Name $svc -ErrorAction Stop
      if ($s.Status -ne 'Stopped') {
        Write-Output ("Stopping service: {0}" -f $svc)
        Stop-Service -Name $svc -Force -ErrorAction Stop
        $s.WaitForStatus('Stopped','00:00:20')
      }
    } catch {
      Write-Warning ("Could not stop service {0} : {1}" -f $svc, $_.Exception.Message)
    }
  }
}

function Start-ServicesInOrder {
  param([string[]]$Services)
  if (-not $Services) { return }
  foreach ($svc in $Services) {
    try {
      $s = Get-Service -Name $svc -ErrorAction Stop
      if ($s.Status -ne 'Running') {
        Write-Output ("Starting service: {0}" -f $svc)
        Start-Service -Name $svc -ErrorAction Stop
        $s.WaitForStatus('Running','00:00:20')
      }
    } catch {
      Write-Warning ("Could not start service {0} : {1}" -f $svc, $_.Exception.Message)
    }
  }
}

function Launch-Apps {
  param([string[]]$Commands)
  if (-not $Commands) { return }
  foreach ($cmd in $Commands) {
    try {
      Write-Output ("Launching: {0}" -f $cmd)
      Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -Command $cmd" | Out-Null
    } catch {
      Write-Warning ("Could not launch: {0}" -f $cmd)
    }
  }
}

function Plan-KillsByPatterns {
  param([string[]]$Patterns)
  if (-not $Patterns) { return @() }
  $matches = @()
  Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name
    $hit = $false
    foreach ($p in $Patterns) { if ($n -like $p) { $hit = $true; break } }
    if ($hit) {
      # Get additional context for node processes
      $context = ""
      if ($n -like "node*") {
        try {
          $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
          $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).ParentProcessId
          $parentName = ""
          if ($parentId) {
            $parentName = (Get-Process -Id $parentId -ErrorAction SilentlyContinue).ProcessName
          }
          
          if ($cmdLine) {
            # Extract useful info from command line
            if ($cmdLine -match "localhost:(\d+)") { $context += " (serving :$($matches[1]))" }
            if ($cmdLine -match "--port\s+(\d+)") { $context += " (port $($matches[1]))" }
            if ($cmdLine -match "npm|yarn|pnpm") { $context += " (package manager)" }
            if ($cmdLine -match "webpack|vite|rollup") { $context += " (build tool)" }
            if ($cmdLine -match "express|fastify|koa") { $context += " (web server)" }
            if ($cmdLine -match "react|vue|angular") { $context += " (frontend dev)" }
            if ($parentName) { $context += " (parent: $parentName)" }
          }
        } catch {
          # Ignore errors getting process details
        }
      }
      
      $matches += [PSCustomObject]@{
        Name  = $_.Name
        PID   = $_.Id
        RAMMB = "{0:N2}" -f ($_.WorkingSet64 / 1MB)
        Context = $context
      }
    }
  }
  return $matches
}

function Confirm-KillChrome {
  param([object[]]$Planned, [switch]$Force)
  $chromeHits = $Planned | Where-Object { $_.Name -like "chrome*" }
  if (-not $chromeHits -or $Force) { return $true }
  Write-Host ""
  Write-Host "Chrome processes detected:" -ForegroundColor Yellow
  $chromeHits | Format-Table Name,PID,RAMMB -AutoSize | Out-Host
  $q = Read-Host "Kill ALL Chrome processes now? (y/N)"
  return ($q -match '^(y|yes)$')
}

function Restore-ChromeSession {
  # Try to reopen last session (tabs) explicitly
  try {
    Start-Process -FilePath "chrome.exe" -ArgumentList "--restore-last-session" | Out-Null
  } catch {
    Write-Warning "Failed to relaunch Chrome with --restore-last-session"
  }
}

function Pick-Processes-OGV {
  param([object[]]$Planned)
  # If Out-GridView isn't available (Core without GUI), return all planned
  if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
    Write-Warning "Out-GridView not available; selecting all planned targets."
    return $Planned
  }
  if (-not $Planned -or $Planned.Count -eq 0) { return @() }
  $sel = $Planned | Select-Object Name, PID, RAMMB | Out-GridView -Title "Select processes to terminate (multi-select), OK to proceed; Cancel to kill none" -PassThru
  # Rejoin on PID to get full objects again
  if ($sel) {
    $pids = $sel | ForEach-Object { $_.PID }
    return $Planned | Where-Object { $pids -contains $_.PID }
  }
  return @()
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

# ----- Profiles -----
$Profiles = Load-Profiles -Path $profilesPath

if ($ListProfiles) {
  if ($Profiles.PSObject.Properties.Name.Count -eq 0) {
    Write-Output ("No profiles found at {0}" -f $profilesPath)
  } else {
    Write-Output ("Profiles from {0}:" -f $profilesPath)
    $Profiles.PSObject.Properties.Name | Sort-Object | ForEach-Object { Write-Output (" - {0}" -f $_) }
  }
  return
}

# --- Optional service assessment (pre-step) ---
$assessScript = Join-Path $projectRoot "assess_services.ps1"
if ($Profile -and $ServiceAssess -and (Test-Path $assessScript)) {
  Write-Output ("Running service assessment for profile '{0}'..." -f $Profile)

  $args = @("-File", $assessScript, "-Mode", $Profile)
  if ($ServiceApply)      { $args += "-Apply" }
  if ($ServicePromptEach) { $args += "-PromptEach" }
  # If you prefer to assess the live system even if running-services.csv exists:
  # $args += "-Live"

  # Run synchronously; assessor writes CSVs to .\out by itself
  & powershell.exe -ExecutionPolicy Bypass @args
  Write-Output "Service assessment complete. See .\out\service_assessment.csv"
}

# ----- Apply profile (optional) -----
$defaultJunk = @(
  "msedge*", "Adobe*", "CreativeCloud*",
  "Apple*Software*Update*", "GoogleUpdate*",
  "OfficeClickToRun*", "MSOSync*", "OneDriveSetup*"
)

$ProfileCfg = $null
$plannedKills = @()
$usedKillList = @()

# Show profile menu if no profile was specified via parameter
if (-not $Profile) {
  $Profile = Show-ProfileMenu -Profiles $Profiles
}

if ($Profile) {
  if ($Profiles.$Profile) {
    $ProfileCfg = $Profiles.$Profile
    Write-Output ("Applying profile: {0}" -f $Profile)

    # Services to stop pre-capture
    if ($ProfileCfg.StopServicesPre) {
      if ($DryRun) {
        Write-Output "DRY RUN: would Stop services (pre):"
        $ProfileCfg.StopServicesPre | ForEach-Object { Write-Output (" - {0}" -f $_) }
      } else {
        Stop-ServicesInOrder -Services $ProfileCfg.StopServicesPre
      }
    }

    # Compose kill list
    if ($ProfileCfg.KillProcesses) { $usedKillList += $ProfileCfg.KillProcesses }
    $usedKillList += $defaultJunk
  } else {
    Write-Warning ("Profile not found: {0} (use -ListProfiles to see available)" -f $Profile)
    $usedKillList += $defaultJunk
  }
} else {
  Write-Output "No profile specified; using default junk-kill list."
  $usedKillList += $defaultJunk
}

# PLAN: what would we kill?
$plannedKills = Plan-KillsByPatterns -Patterns $usedKillList
$planPath = Join-Path $outDir ("planned-kills{0}.csv" -f ($(if($Profile){"_"+$Profile}else{""})))
$plannedKills | Export-Csv $planPath -NoTypeInformation
Write-Output ("Planned kills: {0} (see {1})" -f $plannedKills.Count, $planPath)

# Display planned kills inline with RAM usage and context
if ($plannedKills.Count -gt 0) {
  Write-Output ""
  Write-Output "Planned processes to terminate:"
  Write-Output "================================="
  $plannedKills | Sort-Object Name | ForEach-Object {
    $line = ("{0,-30} PID: {1,6} RAM: {2,8}" -f $_.Name, $_.PID, $_.RAMMB)
    if ($_.Context) { $line += $_.Context }
    Write-Output $line
  }
  Write-Output ""
} else {
  Write-Output "No processes match the kill patterns."
}

# Confirmation prompt (unless -DryRun)
$selectedToKill = $plannedKills
if (-not $DryRun -and $plannedKills.Count -gt 0) {
  Write-Output ""
  $confirm = Read-Host "Proceed with terminating these processes? [Y/n]"
  if ($confirm -match '^(n|no)$') {
    Write-Output "Process termination cancelled by user."
    $selectedToKill = @()
  } else {
    # Interactive pick with Out-GridView
    $selectedToKill = Pick-Processes-OGV -Planned $plannedKills
    Write-Output ("User selected {0} processes to terminate." -f $selectedToKill.Count)
  }
}

# Confirm Chrome specifically (unless -ForceChrome or -DryRun)
$okToKillChrome = $true
if (-not $DryRun) {
  $okToKillChrome = Confirm-KillChrome -Planned $selectedToKill -Force:$ForceChrome
}

# Execute
if (-not $DryRun) {
  $nonChrome = $selectedToKill | Where-Object { $_.Name -notlike "chrome*" }
  foreach ($p in $nonChrome) {
    try { Stop-Process -Id $p.PID -Force -ErrorAction Stop } catch { Write-Warning ("Could not kill {0} ({1}): {2}" -f $p.Name, $p.PID, $_.Exception.Message) }
  }
  if ($okToKillChrome) {
    $chromes = $selectedToKill | Where-Object { $_.Name -like "chrome*" }
    foreach ($p in $chromes) {
      try { Stop-Process -Id $p.PID -Force -ErrorAction Stop } catch { Write-Warning ("Could not kill {0} ({1}): {2}" -f $p.Name, $p.PID, $_.Exception.Message) }
    }
  } else {
    Write-Output "Skipped killing Chrome by user choice."
  }
} else {
  Write-Output "DRY RUN: no processes terminated."
}

# ----- Perf capture via typeperf -----
if ($Capture) {
  Write-Output ("Collecting perf data for {0}s at {1}s interval..." -f $DurationSecs, $IntervalSecs)
  $sampleCnt = [int]([math]::Ceiling($DurationSecs / $IntervalSecs))
  typeperf `
    "\Processor(_Total)\% Processor Time" `
    "\Memory\Available MBytes" `
    "\Process(*)\% Processor Time" `
    "\Process(*)\ID Process" `
    -si $IntervalSecs -sc $sampleCnt -f CSV -o $csvInput
} else {
  Write-Output "Capture is opt-in. Skipping typeperf (use -Capture to enable)."
}

# ----- Services / PID mapping outputs -----
Write-Output "Dumping running services and PID map..."
Get-Service | Where-Object {$_.Status -eq 'Running'} |
  Select-Object Name, DisplayName, Status, StartType |
  Export-Csv (Join-Path $outDir "running-services.csv") -NoTypeInformation

Get-CimInstance Win32_Service |
  Where-Object { $_.ProcessId -ne 0 } |
  Select-Object Name, DisplayName, ProcessId |
  Export-Csv (Join-Path $outDir "service-process-map.csv") -NoTypeInformation

# ----- Transform + report -----
if (Test-Path $csvInput) {
  Write-Output "Transforming CSV and building report..."
  py (Join-Path $projectRoot "perf_transform_cli.py")
  py (Join-Path $projectRoot "make_report.py")
  $reportPath = Join-Path $outDir "report.html"
  if (Test-Path $reportPath) { Invoke-Item $reportPath }
} else {
  Write-Output "No capture CSV present; skipping transform/report."
}

# ----- Optional restore -----
if ($RestoreAfter) {
  if ($ProfileCfg) {
    Write-Output ("Restoring from profile: {0}" -f $Profile)
    if ($ProfileCfg.StartServicesPost) {
      if ($DryRun) {
        Write-Output "DRY RUN: would Start services (post):"
        $ProfileCfg.StartServicesPost | ForEach-Object { Write-Output (" - {0}" -f $_) }
      } else {
        Start-ServicesInOrder -Services $ProfileCfg.StartServicesPost
      }
    }
    if ($ProfileCfg.LaunchAppsPost) {
      if ($DryRun) {
        Write-Output "DRY RUN: would Launch apps (post):"
        $ProfileCfg.LaunchAppsPost | ForEach-Object { Write-Output (" - {0}" -f $_) }
      } else {
        Launch-Apps -Commands $ProfileCfg.LaunchAppsPost
      }
    }
  }

  if ($RestoreChrome) {
    if ($DryRun) {
      Write-Output "DRY RUN: would relaunch Chrome with --restore-last-session"
    } else {
      Restore-ChromeSession
    }
  }
}

Write-Output ("Done. Output artifacts in: {0}" -f $outDir)