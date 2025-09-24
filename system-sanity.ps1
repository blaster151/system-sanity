# system-sanity.ps1
# Triage + perf snapshot (typeperf) + service maps + CSV transform + optional profiles
# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -DurationSecs 60
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -DurationSecs 90 -Profile gaming
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile dev -RestoreAfter
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -ListProfiles
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -ShowChanges
#   powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -CleanupSpace

param(
  [int]$DurationSecs = 120,
  [int]$IntervalSecs = 5,
  [string]$Profile,           # e.g., "gaming", "dev", "normal"
  [switch]$RestoreAfter,      # if present, try to restore services/apps defined by the profile after capture
  [switch]$ListProfiles,      # list available profiles and exit
  [switch]$DryRun,            # plan-only; do NOT kill/stop/start/launch
  [switch]$ForceChrome,       # suppress interactive confirm for Chrome kills
  [switch]$RestoreChrome,     # explicitly relaunch Chrome with --restore-last-session
  [switch]$Capture,           # only collect perf data if explicitly set
  [switch]$ServiceAssess,     # run assess_services.ps1 up front
  [switch]$ServiceApply,      # actually change startup type/stop services
  [switch]$ServicePromptEach, # prompt per service when applying
  [switch]$ShowChanges,       # show permanent changes log and exit
  [switch]$CleanupSpace       # analyze and cleanup boot drive space
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

function Get-ProcessWindowTitle {
  param([int]$ProcessId)
  try {
    # Use Windows API to get window titles
    Add-Type -TypeDefinition @"
      using System;
      using System.Runtime.InteropServices;
      using System.Text;
      
      public class Win32 {
        [DllImport("user32.dll")]
        public static extern IntPtr GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        
        [DllImport("user32.dll")]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
        
        [DllImport("user32.dll")]
        public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
        
        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        
        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);
        
        public const uint GW_HWNDNEXT = 2;
      }
"@
    
    $titles = @()
    $hWnd = [Win32]::FindWindow($null, $null)
    
    while ($hWnd -ne [IntPtr]::Zero) {
      $windowProcessId = 0
      [Win32]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)
      
      if ($windowProcessId -eq $ProcessId) {
        $titleLength = [Win32]::GetWindowTextLength($hWnd)
        if ($titleLength -gt 0 -and [Win32]::IsWindowVisible($hWnd)) {
          $title = New-Object System.Text.StringBuilder($titleLength + 1)
          [Win32]::GetWindowText($hWnd, $title, $title.Capacity)
          $titleText = $title.ToString()
          if ($titleText -and $titleText -ne "") {
            $titles += $titleText
          }
        }
      }
      
      $hWnd = [Win32]::GetWindow($hWnd, [Win32]::GW_HWNDNEXT)
    }
    
    return $titles | Sort-Object -Unique
  } catch {
    return @()
  }
}

# Service assessment functions (from assess_services.ps1)
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
  if ($n -like "wlan*" -or $n -like "netman" -or $n -like "dhcp") { $tags += "network" }
  if ($n -like "defragsvc") { $tags += "storage-opt" }

  if ($tags.Count -eq 0) { $tags += "misc" }
  return $tags
}

function Get-ServiceOpinion([string[]]$tags) {
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

  return [pscustomobject]@{ Dev=$dev; Gaming=$game; Normal=$normal }
}

function Assess-Services {
  param([string]$Mode)
  
  $services = Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, Description, ProcessId
  $assess = @()

  foreach ($svc in $services | Sort-Object Name) {
    $name  = $svc.Name
    $disp  = $svc.DisplayName
    $desc  = $svc.Description
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "(no description)" }
    $state = $svc.State
    $start = $svc.StartMode
    if ($start -like "Auto*") { $start = "Auto" }

    $tags  = Get-ServiceTags -name $name -display $disp
    $op    = Get-ServiceOpinion -tags $tags

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

    # Get RAM usage for running services
    $ramMB = 0
    if ($state -eq "Running" -and $svc.ProcessId -and $svc.ProcessId -ne 0) {
      try {
        $process = Get-Process -Id $svc.ProcessId -ErrorAction SilentlyContinue
        if ($process) {
          $ramMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
        }
      } catch {
        # Ignore errors getting process details
      }
    }

    $assess += [pscustomobject]@{
      Name        = $name
      DisplayName = $disp
      Description = $desc
      Tags        = ($tags -join ",")
      StartType   = $start
      State       = $state
      ProcessId   = $svc.ProcessId
      RAMMB       = $ramMB
      Needed_Dev  = $op.Dev
      Needed_Gaming = $op.Gaming
      Needed_Normal = $op.Normal
      Needed_In_Current_Mode = $neededInMode
      Recommendation = $recommendation
    }
  }
  
  return $assess
}

function Get-QuickCpuSample {
  param([int[]]$ProcessIds)
  if (-not $ProcessIds -or $ProcessIds.Count -eq 0) { return @{} }

  $cpuData = @{}
  try {
    # Get CPU counters for all processes in one call
    $counters = $ProcessIds | ForEach-Object { "\Process($(Get-Process -Id $_ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName))\% Processor Time" }
    $counterData = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue

    if ($counterData) {
      foreach ($sample in $counterData.CounterSamples) {
        $processName = $sample.InstanceName
        $cpuValue = [math]::Round($sample.CookedValue, 2)
        $cpuData[$processName] = $cpuValue
      }
    }
  } catch {
    # Fallback: try individual process sampling
    foreach ($pid in $ProcessIds) {
      try {
        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($process) {
          $counter = "\Process($($process.ProcessName))\% Processor Time"
          $sample = Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
          if ($sample) {
            $cpuData[$process.ProcessName] = [math]::Round($sample.CounterSamples[0].CookedValue, 2)
          }
        }
      } catch {
        # Ignore individual process errors
      }
    }
  }
  return $cpuData
}

function Get-SmartProcessContext {
  param([object]$Process, [string]$ProcessName)

  $context = ""
  $hasUnsavedWork = $false
  $isImportantBrowser = $false

  try {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue).CommandLine
    $windowTitles = Get-ProcessWindowTitle -ProcessId $Process.Id

    # VS Code / Editor unsaved work detection
    if ($ProcessName -like "Code*") {
      $hasUnsavedWork = $false

      # Check window titles for unsaved indicators
      foreach ($title in $windowTitles) {
        if ($title -match "•" -or $title -match "\*") {
          $hasUnsavedWork = $true
          break
        }
      }

      # Check for workspace folders or files
      if ($cmdLine -and $cmdLine -match '"([^"]+)"') {
        $workspace = Split-Path $matches[1] -Leaf
        $context += " (workspace: $workspace)"
      } else {
        $context += " (code editor)"
      }

      if ($hasUnsavedWork) {
        $context += " [UNSAVED WORK DETECTED]"
      }
    }

    # Edge process discrimination
    if ($ProcessName -like "msedge*") {
      if ($ProcessName -eq "msedge.exe") {
        # Main browser - check for actual tabs
        $hasImportantTabs = $false
        foreach ($title in $windowTitles) {
          if ($title -and $title -notmatch "^(Microsoft Edge|New Tab|about:blank)$") {
            $hasImportantTabs = $true
            break
          }
        }

        if ($hasImportantTabs) {
          $context += " (browser with tabs)"
          $isImportantBrowser = $true
        } else {
          $context += " (browser)"
        }
      } else {
        # WebView or other Edge processes
        if ($cmdLine) {
          if ($cmdLine -match "Widgets|widget") {
            $context += " (widgets)"
          } elseif ($cmdLine -match "PWA|app") {
            $context += " (PWA/app)"
          } else {
            $context += " (webview)"
          }
        }
      }
    }

    # Node.js specific context
    if ($ProcessName -like "node*") {
      if ($cmdLine) {
        if ($cmdLine -match "localhost:(\d+)") { $context += " (serving :$($matches[1]))" }
        if ($cmdLine -match "--port\s+(\d+)") { $context += " (port $($matches[1]))" }
        if ($cmdLine -match "npm|yarn|pnpm") { $context += " (package manager)" }
        if ($cmdLine -match "webpack|vite|rollup") { $context += " (build tool)" }
        if ($cmdLine -match "express|fastify|koa") { $context += " (web server)" }
        if ($cmdLine -match "react|vue|angular") { $context += " (frontend dev)" }
      }
    }

    # Generic document context for other applications
    if (-not $context -and $cmdLine) {
      if ($cmdLine -match '"([^"]+\.(pdf|txt|rtf|odt|doc|docx|xls|xlsx|ppt|pptx|md)[^"]*)"') {
        $docName = Split-Path $matches[1] -Leaf
        $context += " (doc: $docName)"
      }
    }

    # Use window titles as fallback context
    if (-not $context -and $windowTitles.Count -gt 0) {
      $mainTitle = $windowTitles[0]
      if ($mainTitle -match "(.+?)(?:\s*-\s*(.+))?$") {
        $appPart = $matches[1]
        $docPart = $matches[2]

        if ($docPart -and $docPart -notmatch "^(Untitled|New Document|Document\d*)$") {
          $context += " (doc: $docPart)"
        } else {
          $context += " ($appPart)"
        }
      }
    }

  } catch {
    # Ignore errors getting process details
  }

  return @{
    Context = $context
    HasUnsavedWork = $hasUnsavedWork
    IsImportantBrowser = $isImportantBrowser
  }
}

function Plan-KillsByPatterns {
  param([object[]]$Patterns)
  if (-not $Patterns) { return @() }
  $processMatches = @()
  $matchingProcesses = @()

  # Convert old format (simple strings) to new format (objects) for backward compatibility
  $normalizedPatterns = @()
  foreach ($p in $Patterns) {
    if ($p -is [string]) {
      # Old format: simple string pattern
      $normalizedPatterns += @{
        pattern = $p
        promptUser = $false
        reason = ""
      }
    } else {
      # New format: object with pattern, promptUser, reason
      $normalizedPatterns += $p
    }
  }

  # First pass: collect matching processes
  Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name
    $hit = $false
    $matchingPattern = $null

    foreach ($p in $normalizedPatterns) {
      if ($n -like $p.pattern) {
        $hit = $true
        $matchingPattern = $p
        break
      }
    }

    if ($hit) {
      $matchingProcesses += @{
        Process = $_
        Pattern = $matchingPattern
      }
    }
  }

  # Get CPU data for all matching processes
  $cpuData = Get-QuickCpuSample -ProcessIds ($matchingProcesses | ForEach-Object { $_.Process.Id })

  # Second pass: build detailed process info
  $matchingProcesses | ForEach-Object {
    $process = $_.Process
    $pattern = $_.Pattern
    $n = $process.Name
      # Get additional context for various processes
      $context = ""
      try {
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue).CommandLine
        $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue).ParentProcessId
        $parentName = ""
        if ($parentId) {
          $parentName = (Get-Process -Id $parentId -ErrorAction SilentlyContinue).ProcessName
        }
        
        # Get window titles for additional context
        $windowTitles = Get-ProcessWindowTitle -ProcessId $process.Id
        
        # Node.js specific context
        if ($n -like "node*") {
          if ($cmdLine) {
            if ($cmdLine -match "localhost:(\d+)") { $context += " (serving :$($matches[1]))" }
            if ($cmdLine -match "--port\s+(\d+)") { $context += " (port $($matches[1]))" }
            if ($cmdLine -match "npm|yarn|pnpm") { $context += " (package manager)" }
            if ($cmdLine -match "webpack|vite|rollup") { $context += " (build tool)" }
            if ($cmdLine -match "express|fastify|koa") { $context += " (web server)" }
            if ($cmdLine -match "react|vue|angular") { $context += " (frontend dev)" }
            if ($parentName) { $context += " (parent: $parentName)" }
          }
        }
        
        # Typora (markdown editor) context
        if ($n -like "Typora*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+\.md[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } elseif ($cmdLine -and $cmdLine -match '"([^"]+\.txt[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } else {
            $context += " (markdown editor)"
          }
        }
        
        # VS Code context
        if ($n -like "Code*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+)"') {
            $workspace = Split-Path $matches[1] -Leaf
            $context += " (workspace: $workspace)"
          } else {
            $context += " (code editor)"
          }
        }
        
        # Chrome/Edge context
        if ($n -like "chrome*" -or $n -like "msedge*") {
          $context += " (browser)"
        }
        
        # Office applications context
        if ($n -like "WINWORD*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+\.docx?[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } else {
            $context += " (Word)"
          }
        }
        if ($n -like "EXCEL*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+\.xlsx?[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } else {
            $context += " (Excel)"
          }
        }
        if ($n -like "POWERPNT*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+\.pptx?[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } else {
            $context += " (PowerPoint)"
          }
        }
        
        # Notepad++ context
        if ($n -like "notepad++*") {
          if ($cmdLine -and $cmdLine -match '"([^"]+)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          } else {
            $context += " (text editor)"
          }
        }
        
        # Generic document context for other applications
        if (-not $context -and $cmdLine) {
          if ($cmdLine -match '"([^"]+\.(pdf|txt|rtf|odt|doc|docx|xls|xlsx|ppt|pptx|md)[^"]*)"') {
            $docName = Split-Path $matches[1] -Leaf
            $context += " (doc: $docName)"
          }
        }
        
        # Use window titles as fallback context for applications without good command line info
        if (-not $context -and $windowTitles.Count -gt 0) {
          $mainTitle = $windowTitles[0]
          # Extract meaningful parts from window titles
          if ($mainTitle -match "(.+?)(?:\s*-\s*(.+))?$") {
            $appPart = $matches[1]
            $docPart = $matches[2]
            
            # Skip generic titles like "Untitled" or "New Document"
            if ($docPart -and $docPart -notmatch "^(Untitled|New Document|Document\d*)$") {
              $context += " (title: $docPart)"
            } elseif ($appPart -and $appPart.Length -lt 50) {
              $context += " (title: $appPart)"
            }
          }
        }
        
      } catch {
        # Ignore errors getting process details
      }
      
      # Get CPU usage for this process
      $cpuPercent = if ($cpuData.ContainsKey($process.Name)) { $cpuData[$process.Name] } else { 0.0 }
      
      $processMatches += [PSCustomObject]@{
        Name  = $process.Name
        PID   = $process.Id
        RAMMB = "{0:N2}" -f ($process.WorkingSet64 / 1MB)
        CPUPercent = $cpuPercent
        Context = $context
        Pattern = $pattern.pattern
        PromptUser = $pattern.promptUser
        Reason = $pattern.reason
      }
    }
  return $processMatches
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

function Manage-WindowsWidgets {
  param([switch]$Apply, [switch]$PromptEach)

  Write-Output ""
  Write-Output "=== WINDOWS WIDGETS DETECTION ==="

  # Check if Windows Widgets service is running
  $widgetsSvc = Get-Service -Name "WidgetsService" -ErrorAction SilentlyContinue
  $widgetsRunning = $false

  if ($widgetsSvc -and $widgetsSvc.Status -eq "Running") {
    Write-Output "Windows Widgets service is currently RUNNING."
    $widgetsRunning = $true
  } else {
    Write-Output "Windows Widgets service is not currently running."
    return $false
  }

  # Check if widgets processes are running
  $widgetsProcesses = Get-Process -Name "widg*" -ErrorAction SilentlyContinue
  if ($widgetsProcesses.Count -gt 0) {
    Write-Output ("Found {0} Windows Widgets processes:" -f $widgetsProcesses.Count)
    $widgetsProcesses | ForEach-Object {
      Write-Output ("  - {0} (PID: {1})" -f $_.ProcessName, $_.Id)
    }
  }

  if (-not $Apply) {
    Write-Output "Windows Widgets detected! Use -Apply to disable it."
    return $true
  }

  if ($PromptEach) {
    Write-Host ""
    Write-Host "Windows Widgets is running and may be spawning unwanted Edge processes." -ForegroundColor Yellow
    Write-Host "Choose how to handle it:" -ForegroundColor Cyan
    Write-Host "  a) Disable until next reboot (temporary)" -ForegroundColor Green
    Write-Host "  b) Disable indefinitely (permanent)" -ForegroundColor Green
    Write-Host "  c) Leave it alone" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Enter choice (a/b/c)"
    switch ($choice) {
      "a" { return Disable-WindowsWidgets -Temporary }
      "b" { return Disable-WindowsWidgets -Permanent }
      default { Write-Output "Leaving Windows Widgets unchanged."; return $false }
    }
  } else {
    # Non-interactive: disable temporarily
    Write-Output "Disabling Windows Widgets temporarily..."
    return Disable-WindowsWidgets -Temporary
  }
}

function Track-PermanentChange {
  param([string]$ChangeType, [string]$Description, [string]$RevertCommand)

  $changeLogPath = Join-Path $outDir "permanent-changes.csv"

  # Create CSV header if it doesn't exist
  if (-not (Test-Path $changeLogPath)) {
    [pscustomobject]@{
      Timestamp = "Timestamp"
      ChangeType = "ChangeType"
      Description = "Description"
      RevertCommand = "RevertCommand"
      Reverted = "Reverted"
    } | Export-Csv -Path $changeLogPath -NoTypeInformation
  }

  # Log the change
  [pscustomobject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ChangeType = $ChangeType
    Description = $Description
    RevertCommand = $RevertCommand
    Reverted = "false"
  } | Export-Csv -Path $changeLogPath -NoTypeInformation -Append

  Write-Output ("Permanent change logged: {0}" -f $Description)
}

function Show-PermanentChanges {
  $changeLogPath = Join-Path $projectRoot "out/permanent-changes.csv"

  if (Test-Path $changeLogPath) {
    Write-Output ""
    Write-Output "=== PERMANENT CHANGES LOG ==="
    $changes = Import-Csv -Path $changeLogPath
    $activeChanges = $changes | Where-Object { $_.Reverted -eq "false" }

    if ($activeChanges.Count -gt 0) {
      $activeChanges | Format-Table -AutoSize Timestamp, ChangeType, Description
      Write-Output ""
      Write-Output "To revert changes, edit the CSV file or delete it to reset tracking."
    } else {
      Write-Output "No active permanent changes."
    }
  }
}

function Disable-WindowsWidgets {
  param([switch]$Temporary, [switch]$Permanent)

  $success = $false

  try {
    if ($Temporary) {
      # Stop the service temporarily (will restart on reboot)
      Stop-Service -Name "WidgetsService" -Force -ErrorAction Stop
      Write-Output "Windows Widgets service stopped (will restart on next reboot)."

      # Kill any running widgets processes
      Get-Process -Name "widg*" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          Stop-Process -Id $_.Id -Force -ErrorAction Stop
          Write-Output ("Terminated {0} (PID: {1})" -f $_.ProcessName, $_.Id)
        } catch {
          Write-Warning ("Could not terminate {0}: {1}" -f $_.ProcessName, $_.Exception.Message)
        }
      }
      $success = $true
    }

    if ($Permanent) {
      # Permanently disable via registry
      $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Dsh"
      if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
      }

      # Set widgets to disabled
      Set-ItemProperty -Path $regPath -Name "IsPrelaunchEnabled" -Value 0 -Type DWord -ErrorAction Stop
      Set-ItemProperty -Path $regPath -Name "IsWidgetEnabled" -Value 0 -Type DWord -ErrorAction Stop

      # Track the permanent change
      $revertCommand = "Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Dsh' -Name 'IsPrelaunchEnabled' -Value 1; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Dsh' -Name 'IsWidgetEnabled' -Value 1; Start-Service -Name 'WidgetsService' -ErrorAction SilentlyContinue"
      Track-PermanentChange -ChangeType "Registry" -Description "Windows Widgets permanently disabled via registry" -RevertCommand $revertCommand

      # Stop the service
      Stop-Service -Name "WidgetsService" -Force -ErrorAction Stop

      # Kill any running widgets processes
      Get-Process -Name "widg*" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          Stop-Process -Id $_.Id -Force -ErrorAction Stop
          Write-Output ("Terminated {0} (PID: {1})" -f $_.ProcessName, $_.Id)
        } catch {
          Write-Warning ("Could not terminate {0}: {1}" -f $_.ProcessName, $_.Exception.Message)
        }
      }

      Write-Output "Windows Widgets permanently disabled (requires logout/login or reboot to take full effect)."
      $success = $true
    }

  } catch {
    Write-Warning ("Failed to disable Windows Widgets: {0}" -f $_.Exception.Message)
  }

  return $success
}

function Get-BootDriveCleanupOpportunities {
  Write-Host ""
  Write-Host "=== BOOT DRIVE SPACE ANALYSIS ===" -ForegroundColor Cyan

  $cleanupOpportunities = @()
  $totalSavings = 0

  try {
    # Get boot drive (usually C:)
    $bootDrive = $env:SystemDrive
    $driveInfo = Get-PSDrive -Name $bootDrive[0] -ErrorAction SilentlyContinue

    if ($driveInfo) {
      $freeGB = [math]::Round($driveInfo.Free / 1GB, 2)
      $usedGB = [math]::Round($driveInfo.Used / 1GB, 2)
      $totalGB = [math]::Round(($driveInfo.Free + $driveInfo.Used) / 1GB, 2)

      Write-Host "Boot drive ($bootDrive): ${usedGB}GB used, ${freeGB}GB free (${totalGB}GB total)" -ForegroundColor White

      # Check Downloads folder for duplicates
      $downloadsPath = Join-Path $env:USERPROFILE "Downloads"
      if (Test-Path $downloadsPath) {
        $duplicates = Find-DownloadDuplicates -Path $downloadsPath
        if ($duplicates.Count -gt 0) {
          $dupeSize = ($duplicates | Measure-Object Size -Sum).Sum / 1GB
          $cleanupOpportunities += @{
            Type = "DuplicateFiles"
            Description = "Remove duplicate files in Downloads folder"
            SizeGB = [math]::Round($dupeSize, 2)
            Action = "Remove-DownloadDuplicates"
            Path = $downloadsPath
          }
        }
      }

      # Check PowerToys update folder
      $powerToysUpdates = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\Updates"
      if (Test-Path $powerToysUpdates) {
        $updateFiles = Get-ChildItem $powerToysUpdates -Recurse -File -ErrorAction SilentlyContinue
        if ($updateFiles.Count -gt 0) {
          $updateSize = ($updateFiles | Measure-Object Length -Sum).Sum / 1GB
          $cleanupOpportunities += @{
            Type = "PowerToysUpdates"
            Description = "Clean PowerToys update files"
            SizeGB = [math]::Round($updateSize, 2)
            Action = "Clean-PowerToysUpdates"
            Path = $powerToysUpdates
          }
        }
      }

      # Check Windows Update cache
      $windowsUpdateCache = Join-Path $env:WINDIR "SoftwareDistribution\Download"
      if (Test-Path $windowsUpdateCache) {
        $cacheFiles = Get-ChildItem $windowsUpdateCache -Recurse -File -ErrorAction SilentlyContinue
        if ($cacheFiles.Count -gt 0) {
          $cacheSize = ($cacheFiles | Measure-Object Length -Sum).Sum / 1GB
          $cleanupOpportunities += @{
            Type = "WindowsUpdateCache"
            Description = "Clean Windows Update download cache"
            SizeGB = [math]::Round($cacheSize, 2)
            Action = "Clean-WindowsUpdateCache"
            Path = $windowsUpdateCache
          }
        }
      }

      # Check temporary files
      $tempFiles = Get-ChildItem $env:TEMP -Recurse -File -ErrorAction SilentlyContinue
      if ($tempFiles.Count -gt 0) {
        $tempSize = ($tempFiles | Measure-Object Length -Sum).Sum / 1GB
        if ($tempSize -gt 0.1) { # Only show if > 100MB
          $cleanupOpportunities += @{
            Type = "TempFiles"
            Description = "Clean temporary files"
            SizeGB = [math]::Round($tempSize, 2)
            Action = "Clean-TempFiles"
            Path = $env:TEMP
          }
        }
      }

      # Show opportunities
      if ($cleanupOpportunities.Count -gt 0) {
        Write-Host ""
        Write-Host "Space cleanup opportunities found:" -ForegroundColor Yellow
        foreach ($opp in $cleanupOpportunities) {
          Write-Host ("  {0,-25} {1,6}GB - {2}" -f $opp.Type, $opp.SizeGB, $opp.Description) -ForegroundColor Green
          $totalSavings += $opp.SizeGB
        }
        Write-Host ("Total potential savings: {0}GB" -f [math]::Round($totalSavings, 2)) -ForegroundColor Cyan

        if ((Read-Host "Perform cleanup operations? (y/N)") -match '^(y|yes)$') {
          Execute-BootDriveCleanup -Opportunities $cleanupOpportunities
        }
      } else {
        Write-Host "No significant cleanup opportunities found." -ForegroundColor Gray
      }
    }
  } catch {
    Write-Host "Could not analyze boot drive space: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function Find-DownloadDuplicates {
  param([string]$Path)

  $files = Get-ChildItem $Path -File -ErrorAction SilentlyContinue
  $duplicates = @()

  # Group by size first (fast)
  $bySize = $files | Group-Object Length
  $largeGroups = $bySize | Where-Object { $_.Count -gt 1 }

  foreach ($group in $largeGroups) {
    # For files with same size, check if they're obvious duplicates by name pattern
    $groupFiles = $group.Group

    for ($i = 0; $i -lt $groupFiles.Count; $i++) {
      for ($j = $i + 1; $j -lt $groupFiles.Count; $j++) {
        $file1 = $groupFiles[$i]
        $file2 = $groupFiles[$j]

        $name1 = $file1.Name
        $name2 = $file2.Name

        # Check for common duplicate patterns
        if ($name1 -match "^(.+?)(\s*\(\d+\))?\.(.+)$" -and $name2 -match "^(.+?)(\s*\(\d+\))?\.(.+)$") {
          $base1 = $matches[1]
          $base2 = $matches[1]

          if ($base1 -eq $base2 -and $matches[3] -eq $matches[3]) {
            # Same base name and extension, likely duplicates
            $duplicates += $file2
          }
        }
      }
    }
  }

  return $duplicates
}

function Execute-BootDriveCleanup {
  param([object[]]$Opportunities)

  $totalCleaned = 0

  foreach ($opp in $Opportunities) {
    Write-Host ("Cleaning {0}..." -f $opp.Type) -ForegroundColor Yellow

    try {
      switch ($opp.Action) {
        "Remove-DownloadDuplicates" {
          $duplicates = Find-DownloadDuplicates -Path $opp.Path
          foreach ($file in $duplicates) {
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $totalCleaned += $file.Length
            Write-Host ("  Removed: {0}" -f $file.Name) -ForegroundColor Green
          }
        }
        "Clean-PowerToysUpdates" {
          $files = Get-ChildItem $opp.Path -Recurse -File
          foreach ($file in $files) {
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $totalCleaned += $file.Length
          }
          Write-Host ("  Cleaned PowerToys update files" -f $opp.Path) -ForegroundColor Green
        }
        "Clean-WindowsUpdateCache" {
          # Be more careful with Windows Update cache
          $oldFiles = Get-ChildItem $opp.Path -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
          foreach ($file in $oldFiles) {
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $totalCleaned += $file.Length
          }
          Write-Host ("  Cleaned old Windows Update cache files" -f $opp.Path) -ForegroundColor Green
        }
        "Clean-TempFiles" {
          $files = Get-ChildItem $opp.Path -Recurse -File
          foreach ($file in $files) {
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $totalCleaned += $file.Length
          }
          Write-Host ("  Cleaned temporary files" -f $opp.Path) -ForegroundColor Green
        }
      }
    } catch {
      Write-Host ("  Error cleaning {0}: {1}" -f $opp.Type, $_.Exception.Message) -ForegroundColor Red
    }
  }

  $cleanedGB = [math]::Round($totalCleaned / 1GB, 2)
  Write-Host ("Cleanup complete! Recovered {0}GB of space." -f $cleanedGB) -ForegroundColor Cyan
}

function Get-UserPermissionForProcesses {
  param([object[]]$ProcessesNeedingPermission)

  if (-not $ProcessesNeedingPermission -or $ProcessesNeedingPermission.Count -eq 0) {
    return @()
  }

  Write-Host ""
  Write-Host "=== PROCESSES REQUIRING YOUR PERMISSION ===" -ForegroundColor Cyan

  $approvedProcesses = @()
  foreach ($process in $ProcessesNeedingPermission) {
    Write-Host ""
    Write-Host ("Process: {0} (PID: {1})" -f $process.Name, $process.PID) -ForegroundColor Yellow
    Write-Host ("Memory: {0} MB, CPU: {1}%" -f $process.RAMMB, $process.CPUPercent)
    Write-Host ("Reason: {0}" -f $process.Reason) -ForegroundColor Gray

    if ($process.Context) {
      Write-Host ("Context: {0}" -f $process.Context) -ForegroundColor Gray
    }

    $choice = Read-Host "Kill this process? (y/N)"
    if ($choice -match '^(y|yes)$') {
      $approvedProcesses += $process
      Write-Host "✓ Approved for termination" -ForegroundColor Green
    } else {
      Write-Host "✗ Skipped" -ForegroundColor Gray
    }
  }

  Write-Host ""
  Write-Host ("Approved {0} out of {1} processes for termination." -f $approvedProcesses.Count, $ProcessesNeedingPermission.Count) -ForegroundColor Cyan
  return $approvedProcesses
}

function Pick-Processes-OGV {
  param([object[]]$Planned)
  # If Out-GridView isn't available (Core without GUI), return all planned
  if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
    Write-Warning "Out-GridView not available; selecting all planned targets."
    return $Planned
  }
  if (-not $Planned -or $Planned.Count -eq 0) { return @() }
  $sel = $Planned | Select-Object Name, PID, RAMMB, CPUPercent, Reason, Context | Out-GridView -Title "Select processes to terminate (multi-select), OK to proceed; Cancel to kill none" -PassThru
  # Rejoin on PID to get full objects again
  if ($sel) {
    $pids = $sel | ForEach-Object { $_.PID }
    return $Planned | Where-Object { $pids -contains $_.PID }
  }
  return @()
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

if ($ShowChanges) {
  Show-PermanentChanges
  return
}

if ($CleanupSpace) {
  Get-BootDriveCleanupOpportunities
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

# ----- Apply profile (default to "normal" if none specified) -----
$ProfileCfg = $null
$plannedKills = @()
$usedKillList = @()

# Use "normal" profile as default if no profile specified
$effectiveProfile = if ($Profile) { $Profile } else { "normal" }

if ($Profiles.$effectiveProfile) {
  $ProfileCfg = $Profiles.$effectiveProfile
  if ($Profile) {
    Write-Output ("Applying profile: {0}" -f $Profile)
  } else {
    Write-Output ("No profile specified; using default 'normal' profile.")
  }

  # Use kill list from profile
  if ($ProfileCfg.KillProcesses) { $usedKillList += $ProfileCfg.KillProcesses }
} else {
  Write-Warning ("Profile not found: {0} (use -ListProfiles to see available)" -f $effectiveProfile)
  Write-Output "Falling back to minimal process list."
  $usedKillList = @("msedge*", "Adobe*", "CreativeCloud*")
}

# ----- Service Assessment (integrated) -----
Write-Output "Assessing services for $($effectiveProfile) mode..."
$serviceAssessment = Assess-Services -Mode $effectiveProfile

# Show service recommendations
$unneededServices = $serviceAssessment | Where-Object { $_.Recommendation -like "Unneeded generally*" }
$modeSpecificServices = $serviceAssessment | Where-Object { $_.Recommendation -like "Not needed for $($effectiveProfile)*" }

if ($unneededServices.Count -gt 0 -or $modeSpecificServices.Count -gt 0) {
  Write-Host ""
  Write-Host "=== SERVICE RECOMMENDATIONS ===" -ForegroundColor Cyan
  
  if ($unneededServices.Count -gt 0) {
    Write-Host ""
    Write-Host "Services that are generally unneeded (consider setting to Manual and stopping):" -ForegroundColor Yellow
    $unneededServices | Sort-Object RAMMB -Descending | ForEach-Object {
      $ramInfo = if ($_.RAMMB -gt 0) { " (RAM: {0} MB)" -f $_.RAMMB } else { "" }
      Write-Host ("  {0,-30} [{1}] - {2}{3}" -f $_.DisplayName, $_.Name, $_.Description, $ramInfo)
    }
  }
  
  if ($modeSpecificServices.Count -gt 0) {
    Write-Host ""
    Write-Host "Services not needed for $($effectiveProfile) mode (consider stopping during this session):" -ForegroundColor Yellow
    $modeSpecificServices | Sort-Object RAMMB -Descending | ForEach-Object {
      $ramInfo = if ($_.RAMMB -gt 0) { " (RAM: {0} MB)" -f $_.RAMMB } else { "" }
      Write-Host ("  {0,-30} [{1}] - {2}{3}" -f $_.DisplayName, $_.Name, $_.Description, $ramInfo)
    }
  }
  
  Write-Host ""
}

# Services to stop pre-capture (from profile)
if ($ProfileCfg -and $ProfileCfg.StopServicesPre) {
  if ($DryRun) {
    Write-Output "DRY RUN: would Stop services (pre):"
    $ProfileCfg.StopServicesPre | ForEach-Object { Write-Output (" - {0}" -f $_) }
  } else {
    Stop-ServicesInOrder -Services $ProfileCfg.StopServicesPre
  }
}

# PLAN: what would we kill?
$plannedKills = Plan-KillsByPatterns -Patterns $usedKillList
$planPath = Join-Path $outDir ("planned-kills_{0}.csv" -f $effectiveProfile)
$plannedKills | Export-Csv $planPath -NoTypeInformation
Write-Output ("Planned kills: {0} (see {1})" -f $plannedKills.Count, $planPath)

# Display planned kills inline with RAM usage and context
if ($plannedKills.Count -gt 0) {
  Write-Output ""
  Write-Output "Planned processes to terminate:"
  Write-Output "================================="
  $plannedKills | Sort-Object Name | ForEach-Object {
    $cpuInfo = if ($_.CPUPercent -gt 0) { " CPU: {0,5}%" -f $_.CPUPercent } else { " CPU:  0.00%" }
    $permissionIcon = if ($_.PromptUser) { " [USER PERMISSION NEEDED]" } else { "" }
    $line = ("{0,-30} PID: {1,6} RAM: {2,8}{3}{4}" -f $_.Name, $_.PID, $_.RAMMB, $cpuInfo, $permissionIcon)
    if ($_.Context) { $line += $_.Context }
    Write-Output $line
  }
  Write-Output ""
} else {
  Write-Output "No processes match the kill patterns."
}

# Service actions (for unneeded services)
$serviceActions = @()
if (-not $DryRun -and $unneededServices.Count -gt 0) {
  Write-Host ""
  Write-Host "=== SERVICE ACTIONS ===" -ForegroundColor Cyan
  
  foreach ($svc in $unneededServices) {
    $svcName = $svc.Name
    $shouldFlipStartup = ($svc.StartType -ne "Manual")
    $shouldStop = ($svc.State -eq "Running")
    
    $doFlip = $false
    $doStop = $false
    
    if ($ServicePromptEach) {
      Write-Host ""
      Write-Host ("Service: {0}  [{1}]" -f $svc.DisplayName, $svcName) -ForegroundColor Yellow
      Write-Host ("Desc   : {0}" -f $svc.Description)
      Write-Host ("Start  : {0}   State: {1}" -f $svc.StartType, $svc.State)
      if ($shouldFlipStartup) {
        $ans1 = Read-Host "Set StartupType to Manual? (y/N)"
        if ($ans1 -match '^(y|yes)$') { $doFlip = $true }
      }
      if ($shouldStop) {
        $ans2 = Read-Host "Stop service now? (y/N)"
        if ($ans2 -match '^(y|yes)$') { $doStop = $true }
      }
    } else {
      # Non-interactive: apply all recommended changes
      $doFlip = $shouldFlipStartup
      $doStop = $shouldStop
    }
    
    $serviceActions += [pscustomobject]@{
      Name = $svcName
      DisplayName = $svc.DisplayName
      DoFlip = $doFlip
      DoStop = $doStop
      ShouldFlip = $shouldFlipStartup
      ShouldStop = $shouldStop
    }
  }
}

# Confirmation prompt (unless -DryRun)
$selectedToKill = $plannedKills
if (-not $DryRun -and $plannedKills.Count -gt 0) {
  Write-Output ""
  $confirm = Read-Host "Proceed with service changes and process termination? [Y/n]"
  if ($confirm -match '^(n|no)$') {
    Write-Output "Service changes and process termination cancelled by user."
    $selectedToKill = @()
    $serviceActions = @()
  } else {
    # Separate processes that need permission from those that don't
    $autoKillProcesses = $plannedKills | Where-Object { -not $_.PromptUser }
    $permissionNeededProcesses = $plannedKills | Where-Object { $_.PromptUser }

    # Get user permission for processes that need it
    $approvedProcesses = Get-UserPermissionForProcesses -ProcessesNeedingPermission $permissionNeededProcesses

    # Use Out-GridView for remaining processes (those without promptUser flag)
    $selectedToKill = @()
    if ($autoKillProcesses.Count -gt 0) {
      $selectedToKill += $autoKillProcesses
    }
    if ($approvedProcesses.Count -gt 0) {
      $selectedToKill += $approvedProcesses
    }

    # Final selection via Out-GridView (optional refinement)
    if ($selectedToKill.Count -gt 0) {
      Write-Output "Opening process selection dialog for final review..."
      $finalSelection = Pick-Processes-OGV -Planned $selectedToKill
      if ($finalSelection.Count -gt 0) {
        $selectedToKill = $finalSelection
      } else {
        $selectedToKill = @()
      }
    }

    Write-Output ("User selected {0} processes to terminate." -f $selectedToKill.Count)
  }
}

# Handle Windows Widgets (before Chrome confirmation)
$widgetsDisabled = $false
if (-not $DryRun) {
  $widgetsDisabled = Manage-WindowsWidgets -Apply:$ServiceApply -PromptEach:$ServicePromptEach
}

# Confirm Chrome specifically (unless -ForceChrome or -DryRun)
$okToKillChrome = $true
if (-not $DryRun) {
  $okToKillChrome = Confirm-KillChrome -Planned $selectedToKill -Force:$ForceChrome
}

# Execute service changes first (services before processes)
if (-not $DryRun -and $serviceActions.Count -gt 0) {
  Write-Output ""
  Write-Output "=== EXECUTING SERVICE CHANGES ==="
  Write-Output ("Processing {0} service changes..." -f $serviceActions.Count)
  
  $serviceCount = 0
  foreach ($action in $serviceActions) {
    $serviceCount++
    Write-Output ("[{0}/{1}] Processing {2}..." -f $serviceCount, $serviceActions.Count, $action.DisplayName)
    $svcName = $action.Name
    $flipOk = $false
    $stopOk = $false
    $flipErr = ""; $stopErr = ""
    
    if ($action.DoFlip) {
      try {
        Set-Service -Name $svcName -StartupType Manual -ErrorAction Stop
        $flipOk = $true
        Write-Output ("Set {0} startup type to Manual" -f $action.DisplayName)
      } catch {
        try {
          & sc.exe config $svcName start= demand | Out-Null
          $flipOk = $true
          Write-Output ("Set {0} startup type to Manual (via sc.exe)" -f $action.DisplayName)
        } catch {
          $flipErr = $_.Exception.Message
          Write-Warning ("Could not set {0} to Manual: {1}" -f $action.DisplayName, $flipErr)
        }
      }
    }
    
    if ($action.DoStop) {
      try {
        Stop-Service -Name $svcName -Force -ErrorAction Stop
        $stopOk = $true
        Write-Output ("Stopped {0}" -f $action.DisplayName)
      } catch {
        $stopErr = $_.Exception.Message
        Write-Warning ("Could not stop {0}: {1}" -f $action.DisplayName, $stopErr)
      }
    }
  }
  
  Write-Output "Service changes complete."
}

# Execute process termination
if (-not $DryRun) {
  if ($selectedToKill.Count -gt 0) {
    Write-Output ""
    Write-Output "=== EXECUTING PROCESS TERMINATION ==="
    Write-Output ("Terminating {0} processes..." -f $selectedToKill.Count)
    
    $nonChrome = $selectedToKill | Where-Object { $_.Name -notlike "chrome*" }
    $processCount = 0
    foreach ($p in $nonChrome) {
      $processCount++
      Write-Output ("[{0}/{1}] Terminating {2} (PID: {3})..." -f $processCount, $nonChrome.Count, $p.Name, $p.PID)
      try { 
        Stop-Process -Id $p.PID -Force -ErrorAction Stop 
        Write-Output ("Terminated {0} (PID: {1})" -f $p.Name, $p.PID)
      } catch { 
        Write-Warning ("Could not kill {0} ({1}): {2}" -f $p.Name, $p.PID, $_.Exception.Message) 
      }
    }
    
    if ($okToKillChrome) {
      $chromes = $selectedToKill | Where-Object { $_.Name -like "chrome*" }
      if ($chromes.Count -gt 0) {
        Write-Output ("Terminating {0} Chrome processes..." -f $chromes.Count)
        $chromeCount = 0
      foreach ($p in $chromes) {
          $chromeCount++
          Write-Output ("[{0}/{1}] Terminating Chrome {2} (PID: {3})..." -f $chromeCount, $chromes.Count, $p.Name, $p.PID)
        try { 
          Stop-Process -Id $p.PID -Force -ErrorAction Stop 
          Write-Output ("Terminated {0} (PID: {1})" -f $p.Name, $p.PID)
        } catch { 
          Write-Warning ("Could not kill {0} ({1}): {2}" -f $p.Name, $p.PID, $_.Exception.Message) 
          }
        }
      }
    } else {
      Write-Output "Skipped killing Chrome by user choice."
    }
  }
} else {
  Write-Output "DRY RUN: no services changed or processes terminated."
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
Write-Output ""
Write-Output "=== GENERATING REPORTS ==="
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

Write-Output ""
Write-Output "=== COMPLETED ==="
Write-Output ("Done. Output artifacts in: {0}" -f $outDir)