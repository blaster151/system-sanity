# Recent Changes to System Sanity

## November 1, 2025

### 1. Removed Duplicate Implementation
- **Deleted**: `system-sanity.py` - incomplete Python rewrite that lacked many features
- **Kept**: `system-sanity.ps1` - mature, feature-rich PowerShell implementation
- **Reason**: The PowerShell version has significantly more functionality including:
  - Smart process context detection (window titles, command lines)
  - Integrated service assessment with recommendations
  - Windows Widgets detection and management
  - Disk space cleanup features (Package Cache, MSP files)
  - Permanent change tracking with revert commands
  - Performance data capture with typeperf

### 2. Updated Profile Configurations (`profiles.json`)

#### Normal Profile (Base)
- Added `Widget*` pattern (in addition to `widg*`) for better Windows Widgets coverage
- Kills: Edge, WebView, widgets, Adobe, Creative Cloud, updaters, Discord, etc.

#### Gaming Profile (Superset of Normal)
- **NEW**: Added `ms-teams*` (Microsoft Teams)
- **NEW**: Added `iCloud*` (iCloud processes)
- Inherits ALL process kill patterns from Normal profile
- Plus gaming-specific processes: Chrome, VS Code, node, dotnet, msbuild, devenv

#### Dev Profile (Superset of Normal)
- Inherits ALL process kill patterns from Normal profile
- Plus dev-specific processes: Steam, Battle.net, Epic Games

**Key Design**: Gaming and Dev profiles now function as proper supersets - they both include everything from Normal's kill list, plus their own specific additions.

### 3. Enhanced `chrome_debugger_extract.ps1`

Upgraded from proof-of-concept to production-ready tool:

#### Features:
- **Process Analysis**: Analyzes all Chrome and Edge processes with detailed command-line information
- **Tab/Extension Extraction**: Extracts tab URLs, titles, and extension IDs (when remote debugging is enabled)
- **Process Type Detection**: Identifies process types (renderer, GPU, extension background, service worker, etc.)
- **URL Analysis**: Extracts domains from web pages, identifies extensions by ID
- **Memory Usage**: Shows RAM consumption per process
- **Export Capabilities**: Exports both process details and tab information to CSV

#### Usage:
```powershell
# Basic usage (analyzes running browsers, no remote debugging needed for process info)
.\chrome_debugger_extract.ps1

# Include Edge as well as Chrome
.\chrome_debugger_extract.ps1 -IncludeEdge

# Custom ports (if browsers running with remote debugging)
.\chrome_debugger_extract.ps1 -ChromePort 9222 -EdgePort 9223

# Custom output path
.\chrome_debugger_extract.ps1 -OutputPath ".\custom-output.csv"
```

#### Outputs:
- `.\out\browser-tabs-processes.csv` - All browser processes with memory usage and types
- `.\out\browser-tabs.csv` - Tab/extension details (requires remote debugging)

**Note**: To get full tab/extension information, browsers must be started with remote debugging:
```powershell
chrome.exe --remote-debugging-port=9222
msedge.exe --remote-debugging-port=9223
```

### 4. Added Display Configuration Detection

**New Feature**: `system-sanity.ps1` now automatically detects and displays monitor information on startup.

#### Information Displayed:
- **Resolution**: Width x Height for each connected display
- **Refresh Rate**: Hz (when available)
- **Video Memory**: GPU RAM for each adapter
- **Physical Monitor Size**: Actual monitor dimensions in cm and diagonal in inches
- **Monitor Names**: Friendly names from Windows

#### Example Output:
```
=== DISPLAY CONFIGURATION ===
Display 1: NVIDIA GeForce RTX 3080
  Resolution: 2560 x 1440
  Refresh Rate: 144 Hz
  Video Memory: 10 GB

Display 2: Intel(R) UHD Graphics 630
  Resolution: 1920 x 1080
  Refresh Rate: 60 Hz
  Video Memory: 0.13 GB

Physical Monitor Details:
  Monitor 1: 59.7cm x 33.6cm (~27.0 inches diagonal)
  Monitor 2: 47.6cm x 26.8cm (~21.5 inches diagonal)
```

## Regarding `msedgewebview*` Process Respawning

The mysterious respawning of `msedgewebview*` processes could be caused by several Windows components:

### Known Culprits:
1. **Windows Widgets** - Already handled by script (kills `Widget*` and `widg*`)
2. **Windows Search** - Uses Edge WebView2
3. **Windows Shell Experience Host** - System UI components
4. **Microsoft Store Apps** - Many PWAs use Edge WebView2
5. **Windows Task Bar Search** - Search box on taskbar
6. **Windows News and Interests** - Taskbar widget (if enabled)
7. **Microsoft Teams (Personal)** - If installed as PWA
8. **Microsoft 365 Apps** - Office apps can spawn WebView2 processes

### Recommended Investigation:
```powershell
# Run this to see what's starting Edge WebView2 processes
Get-Process msedge* | ForEach-Object {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)"
    [PSCustomObject]@{
        Name = $_.Name
        PID = $_.Id
        CommandLine = $proc.CommandLine
        ParentProcessId = $proc.ParentProcessId
    }
} | Format-Table -AutoSize
```

### Potential Solutions:
- Disable Windows Search integration
- Disable taskbar search box
- Uninstall PWAs from Microsoft Edge
- Check startup programs for Edge-based apps
- Use Task Scheduler to identify scheduled tasks launching Edge components

## Files Changed
- ✅ `profiles.json` - Updated all profiles with new process patterns
- ✅ `chrome_debugger_extract.ps1` - Complete rewrite with enhanced features
- ✅ `system-sanity.ps1` - Added `Get-DisplayInfo()` function
- ❌ `system-sanity.py` - Deleted (incomplete/redundant)

## Python Scripts Retained
The following Python scripts are still needed for data transformation:
- `perf_transform_cli.py` - CSV performance data transformation
- `make_report.py` - HTML report generation
- `perfmon_transform.py` - Alternative transformer with pandas
- `perfmon_transform_nopandas.py` - Lightweight transformer
- `run-sanity.py` - Python wrapper/launcher
