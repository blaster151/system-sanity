<# 
Assess Windows services against usage profiles and optionally reconfigure them.

Usage examples:
  # Dry run, just show opinions (default)
  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1

  # Evaluate for Gaming profile, prompt before changing, apply changes when confirmed
  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode gaming -Apply -PromptEach

  # Evaluate for Dev profile, no changes (report only), but still tell what would change
  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode dev

  # Evaluate only currently running services (ignore CSV), and write outputs
  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Live

  # Interactive mode for Normal profile - prompts user about additional services
  powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractiveNormal

Outputs (all to .\out\):
  service_assessment.csv
  service_actions_taken.csv (if -Apply did anything)
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [ValidateSet("dev","gaming","normal")]
  [string]$Mode = "normal",

  [switch]$Apply,        # actually Set-Service (StartupType Manual) + Stop-Service
  [switch]$PromptEach,   # confirm per "unnecessary" service before change
  [switch]$Live,         # use live Get-CimInstance Win32_Service instead of CSV
  [switch]$InteractiveNormal  # prompt user for additional "normal" services
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSCommandPath
$outDir      = Join-Path $projectRoot "out"
New-Item -Type Directory -Force -Path $outDir | Out-Null

# Load services either from CSV (your earlier export) or live
$services = @()
if ($Live) {
  $services = Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, Description, ProcessId
} else {
  $csv = Join-Path $outDir "running-services.csv"
  if (-not (Test-Path $csv)) {
    Write-Warning "No .\out\running-services.csv found; falling back to live query."
    $services = Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, Description, ProcessId
  } else {
    $raw = Import-Csv $csv
    # Enrich with live description/startmode when possible
    $liveMap = @{}
    Get-CimInstance Win32_Service | ForEach-Object { $liveMap[$_.Name] = $_ }
    foreach ($r in $raw) {
      $wmi = $null
      if ($liveMap.ContainsKey($r.Name)) { $wmi = $liveMap[$r.Name] }
      $services += [pscustomobject]@{
        Name        = $r.Name
        DisplayName = $r.DisplayName
        State       = $r.Status
        StartMode   = if ($wmi) { $wmi.StartMode } else { $r.StartType }
        Description = if ($wmi) { $wmi.Description } else { "" }
        ProcessId   = if ($wmi) { $wmi.ProcessId } else { $null }
      }
    }
  }
}

# --- Heuristic rules ----------------------------------------------------------
function Match-Any([string]$name, [string[]]$patterns) {
  foreach ($p in $patterns) { if ($name -like $p) { return $true } }
  return $false
}

# Tag families by name
function Get-ServiceTags([string]$name, [string]$display) {
  $n = $name.ToLower()
  $d = if ($display) { $display.ToLower() } else { "" }
  $tags = @()

  if ($n -like "mssqlserver" -or $n -like "mssql$*" -or $n -like "sqlserveragent*" -or $n -like "sqlwriter*") { $tags += "sql" }
  if ($n -like "postgresql*" -or $n -like "mysql*" -or $n -like "mariadb*") { $tags += "db" }
  if ($n -like "w3svc" -or $n -like "iisadmin*" -or $n -like "was" -or $n -like "wmsvc*") { $tags += "iis" }
  if ($n -like "docker*" -or $n -like "com.docker.service") { $tags += "docker" }
  if ($n -like "vmms" -or $n -like "vmcompute" -or $n -like "vmicheartbeat*" -or $n -like "vmic*") { $tags += "hyperv" }
  if ($n -like "xbox*" -or $n -like "gamingservices" -or $n -like "xbl*") { $tags += "xbox" }
  if ($n -like "one*" -and $n -like "*sync*") { $tags += "onesync" }
  if ($n -like "onedrivesync*" -or $d -like "*onedrive*") { $tags += "onedrive" }
  if ($n -like "adobearm*" -or $n -like "adobe*update*" -or $d -like "*adobe*") { $tags += "adobe" }
  if ($n -like "gupdate*" -or $n -like "gupdatem*") { $tags += "googleupdate" }
  if ($n -like "apple*" -or $d -like "*apple*") { $tags += "apple" }
  if ($n -like "printspooler" -or $n -like "spooler") { $tags += "print" }
  if ($n -like "fax") { $tags += "fax" }
  if ($n -like "remoteregistry") { $tags += "remote-registry" }
  if ($n -like "diagnosticshub*" -or $n -like "diagsvc" -or $n -like "diagnostic*" -or $n -like "dmwappushsvc") { $tags += "telemetry" }
  if ($n -like "retaildemo") { $tags += "retail" }
  if ($n -like "wsearch") { $tags += "search" }
  if ($n -like "bits") { $tags += "bits" }
  if ($n -like "ssh-agent" -or $n -like "sshd") { $tags += "ssh" }
  if ($n -like "wuauserv") { $tags += "windows-update" }
  if ($n -like "wlan*" -or $n -like "netman" -or $n -like "dhcp" -or $n -like "dnscache" -or $n -like "nlasvc" -or $n -like "netprofm") { $tags += "network" }
  if ($n -like "defragsvc" -or $n -like "disk*" -or $n -like "vss") { $tags += "storage-opt" }
  if ($n -like "themes" -or $n -like "uxtheme") { $tags += "ui" }
  if ($n -like "audio*" -or $n -like "audiosrv" -or $n -like "audiodg") { $tags += "audio" }
  if ($n -like "bluetooth*" -or $n -like "bthserv") { $tags += "bluetooth" }

  if ($tags.Count -eq 0) { $tags += "misc" }
  return $tags
}

# Opinion matrix: Needed? (dev/gaming/normal)
function Get-Opinion([string[]]$tags, [hashtable]$userPreferences = @{}) {
  # Defaults:
  $dev    = $true
  $game   = $true
  $normal = $true

  # "Often not needed" buckets
  if ($tags -contains "fax" -or $tags -contains "retail" -or $tags -contains "remote-registry") {
    $dev=$false; $game=$false; $normal=$false
  }

  # Heavy developer infra
  if ($tags -contains "sql" -or $tags -contains "db" -or $tags -contains "iis" -or $tags -contains "docker" -or $tags -contains "hyperv") {
    $dev=$true;  $game=$false; $normal=$false
  }

  # Xbox stack (some games need it, but many don't if you're not using Xbox/Store titles)
  if ($tags -contains "xbox") {
    $dev=$false; $game=$false; $normal=$false
  }

  # Updaters / telemetry: rarely needed "right now"
  if ($tags -contains "adobe" -or $tags -contains "googleupdate" -or $tags -contains "apple" -or $tags -contains "telemetry") {
    $dev=$false; $game=$false; $normal=$false
  }

  # Print spooler: off for gaming; dev/normal "maybe"
  if ($tags -contains "print") {
    $dev=$false; $game=$false; $normal=$true
  }

  # OneDrive/OneSync: not for gaming; maybe for dev/normal depending on workflow
  if ($tags -contains "onedrive" -or $tags -contains "onesync") {
    $dev=$true;  $game=$false; $normal=$true
  }

  # Search indexer: nice but not essential while gaming / heavy dev
  if ($tags -contains "search") {
    $dev=$false; $game=$false; $normal=$true
  }

  # BITS / Windows Update: keep for normal; pause during gaming/dev if chasing perf
  if ($tags -contains "bits" -or $tags -contains "windows-update") {
    $dev=$false; $game=$false; $normal=$true
  }

  # SSH: dev often wants agent/sshd; not gaming/normal
  if ($tags -contains "ssh") {
    $dev=$true;  $game=$false; $normal=$false
  }

  # Network services: apply user preferences if available
  if ($tags -contains "network") {
    if ($userPreferences.ContainsKey("network")) {
      $normal = $userPreferences["network"]
    } else {
      $normal = $false  # Default to not needed, but can be overridden by user
    }
  }

  # Storage optimization: apply user preferences if available
  if ($tags -contains "storage-opt") {
    if ($userPreferences.ContainsKey("storage-opt")) {
      $normal = $userPreferences["storage-opt"]
    } else {
      $normal = $false  # Default to not needed, but can be overridden by user
    }
  }

  # Audio services: apply user preferences if available
  if ($tags -contains "audio") {
    if ($userPreferences.ContainsKey("audio")) {
      $normal = $userPreferences["audio"]
    } else {
      $normal = $true  # Default to needed for normal use
    }
  }

  # Bluetooth services: apply user preferences if available
  if ($tags -contains "bluetooth") {
    if ($userPreferences.ContainsKey("bluetooth")) {
      $normal = $userPreferences["bluetooth"]
    } else {
      $normal = $false  # Default to not needed, but can be overridden by user
    }
  }

  # UI/Theme services: apply user preferences if available
  if ($tags -contains "ui") {
    if ($userPreferences.ContainsKey("ui")) {
      $normal = $userPreferences["ui"]
    } else {
      $normal = $true  # Default to needed for normal use
    }
  }

  # Telemetry services: apply user preferences if available
  if ($tags -contains "telemetry") {
    if ($userPreferences.ContainsKey("telemetry")) {
      $normal = $userPreferences["telemetry"]
    } else {
      $normal = $false  # Default to not needed, but can be overridden by user
    }
  }

  return [pscustomobject]@{ Dev=$dev; Gaming=$game; Normal=$normal }
}

# Interactive prompts for additional "normal" services
function Get-UserPreferencesForNormal {
  param([string[]]$allTags)
  
  $preferences = @{}
  $uniqueTags = $allTags | Sort-Object -Unique
  
  Write-Host ""
  Write-Host "Additional Services for 'Normal' Mode" -ForegroundColor Cyan
  Write-Host "=====================================" -ForegroundColor Cyan
  Write-Host "Some services might be useful for normal daily use. Would you like to keep any of these running?" -ForegroundColor Yellow
  Write-Host ""
  
  # Network services (WiFi, network management, DHCP)
  if ($uniqueTags -contains "network") {
    Write-Host "Network Services (WiFi, Network Management, DHCP):" -ForegroundColor White
    Write-Host "  These services manage your network connections and internet access." -ForegroundColor Gray
    $response = Read-Host "Do you need network services for normal use? (y/N)"
    $preferences["network"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  # Storage optimization (defrag, disk optimization)
  if ($uniqueTags -contains "storage-opt") {
    Write-Host "Storage Optimization Services:" -ForegroundColor White
    Write-Host "  These services help optimize disk performance and defragment storage." -ForegroundColor Gray
    $response = Read-Host "Do you need storage optimization for normal use? (y/N)"
    $preferences["storage-opt"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  # Additional prompts for specific service types
  if ($uniqueTags -contains "telemetry") {
    Write-Host "Diagnostic/Telemetry Services:" -ForegroundColor White
    Write-Host "  These services help Windows diagnose issues and provide feedback." -ForegroundColor Gray
    $response = Read-Host "Do you want to keep diagnostic services for normal use? (y/N)"
    $preferences["telemetry"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  # Audio services
  if ($uniqueTags -contains "audio") {
    Write-Host "Audio Services:" -ForegroundColor White
    Write-Host "  These services manage audio playback and recording." -ForegroundColor Gray
    $response = Read-Host "Do you need audio services for normal use? (y/N)"
    $preferences["audio"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  # Bluetooth services
  if ($uniqueTags -contains "bluetooth") {
    Write-Host "Bluetooth Services:" -ForegroundColor White
    Write-Host "  These services manage Bluetooth devices and connections." -ForegroundColor Gray
    $response = Read-Host "Do you need Bluetooth services for normal use? (y/N)"
    $preferences["bluetooth"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  # UI/Theme services
  if ($uniqueTags -contains "ui") {
    Write-Host "UI/Theme Services:" -ForegroundColor White
    Write-Host "  These services manage visual themes and user interface elements." -ForegroundColor Gray
    $response = Read-Host "Do you need UI/theme services for normal use? (y/N)"
    $preferences["ui"] = ($response -match '^(y|yes)$')
    Write-Host ""
  }
  
  return $preferences
}

# ------------------------------------------------------------------------------

$assess = @()

# Get user preferences for additional "normal" services if in interactive mode
$userPreferences = @{}
if ($Mode -eq "normal" -and $InteractiveNormal) {
  # First pass: collect all tags to show relevant prompts
  $allTags = @()
  foreach ($svc in $services) {
    $tags = Get-ServiceTags -name $svc.Name -display $svc.DisplayName
    $allTags += $tags
  }
  $userPreferences = Get-UserPreferencesForNormal -allTags $allTags
}

foreach ($svc in $services | Sort-Object Name) {
  $name  = $svc.Name
  $disp  = $svc.DisplayName
  $desc  = $svc.Description
  if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "(no description)" }
  $state = $svc.State
  $start = $svc.StartMode   # Auto | Manual | Disabled (sometimes 'Auto (Delayed Start)' via registry; normalize)
  if ($start -like "Auto*") { $start = "Auto" }

  $tags  = Get-ServiceTags -name $name -display $disp
  $op    = Get-Opinion -tags $tags -userPreferences $userPreferences

  $neededInMode = switch ($Mode) {
    "dev"    { $op.Dev }
    "gaming" { $op.Gaming }
    default  { $op.Normal }
  }

  $neededAtAll = ($op.Dev -or $op.Gaming -or $op.Normal)

  $recommendation = if (-not $neededAtAll) {
    "Unneeded generally: set to Manual; Stop if running"
  } elseif (-not $neededInMode) {
    "Not needed for $($Mode): consider stopping during this mode"
  } else {
    "Needed for $($Mode)"
  }

  $assess += [pscustomobject]@{
    Name        = $name
    DisplayName = $disp
    Description = $desc
    Tags        = ($tags -join ",")
    StartType   = $start
    State       = $state
    Needed_Dev  = $op.Dev
    Needed_Gaming = $op.Gaming
    Needed_Normal = $op.Normal
    Needed_In_Current_Mode = $neededInMode
    Recommendation = $recommendation
  }
}

# Write report
$assessPath = Join-Path $outDir "service_assessment.csv"
$assess | Export-Csv -NoTypeInformation -Path $assessPath
Write-Output ("Wrote: {0}" -f $assessPath)

# Actions: for services "Unneeded generally" -> if StartType != Manual, prompt to change; always offer to stop now
$actions = @()
foreach ($row in $assess) {
  $unneeded = ($row.Recommendation -like "Unneeded generally*")
  if (-not $unneeded) { continue }

  $svcName = $row.Name
  $shouldFlipStartup = ($row.StartType -ne "Manual")

  $doFlip = $false
  $doStop = $false

  if ($Apply) {
    if ($PromptEach) {
      Write-Host ""
      Write-Host ("Service: {0}  [{1}]" -f $row.DisplayName, $svcName) -ForegroundColor Yellow
      Write-Host ("Desc   : {0}" -f $row.Description)
      Write-Host ("Start  : {0}   State: {1}" -f $row.StartType, $row.State)
      if ($shouldFlipStartup) {
        $ans1 = Read-Host "Set StartupType to Manual? (y/N)"
        if ($ans1 -match '^(y|yes)$') { $doFlip = $true }
      }
      $ans2 = Read-Host "Stop service now? (y/N)"
      if ($ans2 -match '^(y|yes)$') { $doStop = $true }
    } else {
      # Non-interactive apply: flip + stop
      $doFlip = $shouldFlipStartup
      $doStop = $true
    }
  }

  $flipOk = $false
  $stopOk = $false
  $flipErr = ""; $stopErr = ""

  if ($Apply -and $doFlip) {
    try {
      # Prefer Set-Service, fallback to sc.exe if needed
      Set-Service -Name $svcName -StartupType Manual -ErrorAction Stop
      $flipOk = $true
    } catch {
      try {
        & sc.exe config $svcName start= demand | Out-Null
        $flipOk = $true
      } catch {
        $flipErr = $_.Exception.Message
      }
    }
  }

  if ($Apply -and $doStop) {
    try {
      Stop-Service -Name $svcName -Force -ErrorAction Stop
      $stopOk = $true
    } catch {
      $stopErr = $_.Exception.Message
    }
  }

  $actions += [pscustomobject]@{
    Name          = $svcName
    DisplayName   = $row.DisplayName
    ActionFlipToManual_Requested = $doFlip
    ActionFlipToManual_Success   = $flipOk
    ActionFlip_Error             = $flipErr
    ActionStopNow_Requested      = $doStop
    ActionStopNow_Success        = $stopOk
    ActionStop_Error             = $stopErr
  }
}

if ($actions.Count -gt 0) {
  $actPath = Join-Path $outDir "service_actions_taken.csv"
  $actions | Export-Csv -NoTypeInformation -Path $actPath
  Write-Output ("Wrote: {0}" -f $actPath)
} else {
  Write-Output ("No changes applied (use -Apply to act, -PromptEach to confirm per service).")
}
