# VS Code Decision Flow Separation - November 4, 2025

## Overview

VS Code processes now have their own **separate all-or-nothing decision point**, just like Chrome processes.

## New Flow

### Step 1: Chrome Decision (First)
```
=== CHROME BROWSER PROCESSES ===
Found 15 Chrome processes consuming 1,234.56 MB total
...
Kill ALL Chrome processes? [y/N]
```

### Step 2: VS Code Decision (Second) ✨ NEW
```
=== VS CODE EDITOR PROCESSES ===
Found 8 VS Code processes consuming 543.21 MB total

Main Editor Process:
Name      PID    RAMMB        Context
----      ---    -----        -------
Code.exe  1234   234.56 MB   (workspace: my-project)

+ 7 helper/extension processes

Open workspaces:
  - my-project

⚠ UNSAVED WORK DETECTED - Files may not be saved!
This will close ALL VS Code processes (including all windows and extensions).
Kill ALL VS Code processes? [y/N]
```

### Step 3: Everything Else (Third)
```
Proceed with service changes and process termination (other processes)? [Y/n]
```

### Step 4: Execution
```
=== EXECUTING PROCESS TERMINATION ===
Terminating 25 total processes (10 other, 8 VS Code, 7 Chrome)...

[Other processes killed first]
[VS Code processes killed second]
[Chrome processes killed last]
```

## Features

### Confirm-KillCode Function

The new function provides:

1. **Process Count & Memory Usage**
   - Shows total VS Code processes and RAM consumption
   - Example: "Found 8 VS Code processes consuming 543.21 MB total"

2. **Main Process Display**
   - Shows the main Code.exe process with context
   - Displays workspace name if available
   - Example: "(workspace: my-project)"

3. **Helper Process Summary**
   - Counts and displays extension/helper processes
   - Example: "+ 7 helper/extension processes"

4. **Open Workspaces List**
   - Shows all unique workspace names from processes
   - Helps user understand what's open

5. **Unsaved Work Detection** ⚠️
   - Detects window titles with `•` or `*` indicators
   - Shows red warning: "⚠ UNSAVED WORK DETECTED - Files may not be saved!"
   - Helps prevent data loss

6. **Clear Warning**
   - States: "This will close ALL VS Code processes (including all windows and extensions)."
   - Users understand the impact

## Scenarios

### Scenario 1: Kill Code, Kill Chrome, Kill Others
```
Kill ALL Chrome processes? [y/N] y
Kill ALL VS Code processes? [y/N] y
Proceed with service changes and process termination (other processes)? [Y/n] y
```
**Result:** Everything gets killed

### Scenario 2: Keep Code, Kill Chrome, Kill Others
```
Kill ALL Chrome processes? [y/N] y
Kill ALL VS Code processes? [y/N] n
Proceed with service changes and process termination (other processes)? [Y/n] y
```
**Result:** VS Code stays running (preserves your work), everything else killed

### Scenario 3: Kill Code Only
```
Kill ALL Chrome processes? [y/N] n
Kill ALL VS Code processes? [y/N] y
Proceed with service changes and process termination (other processes)? [Y/n] n
```
**Result:** Only VS Code gets killed

### Scenario 4: Keep Everything
```
Kill ALL Chrome processes? [y/N] n
Kill ALL VS Code processes? [y/N] n
Proceed with service changes and process termination (other processes)? [Y/n] n
```
**Result:** Nothing gets killed

## Technical Implementation

### Process Separation
```powershell
# Separate Chrome, Code, and other processes
$chromeProcesses = $plannedKills | Where-Object { $_.Name -like "chrome*" }
$codeProcesses = $plannedKills | Where-Object { $_.Name -like "Code*" }
$otherProcesses = $plannedKills | Where-Object { $_.Name -notlike "chrome*" -and $_.Name -notlike "Code*" }
```

### Sequential Confirmation
```powershell
# 1. Chrome decision (first)
$selectedChromeProcesses = @()
if ($chromeProcesses.Count -gt 0) {
  $okToKillChrome = Confirm-KillChrome -Planned $chromeProcesses
  if ($okToKillChrome) {
    $selectedChromeProcesses = $chromeProcesses
  }
}

# 2. VS Code decision (second) ✨ NEW
$selectedCodeProcesses = @()
if ($codeProcesses.Count -gt 0) {
  $okToKillCode = Confirm-KillCode -Planned $codeProcesses
  if ($okToKillCode) {
    $selectedCodeProcesses = $codeProcesses
  }
}

# 3. Other processes decision (third)
$confirm = Read-Host "Proceed with service changes and process termination (other processes)? [Y/n]"
```

### Execution Order
```powershell
$totalToKill = $selectedToKill.Count + $selectedCodeProcesses.Count + $selectedChromeProcesses.Count

# 1. Kill other processes first
foreach ($p in $selectedToKill) { ... }

# 2. Kill VS Code processes second
foreach ($p in $selectedCodeProcesses) { ... }

# 3. Kill Chrome processes last
foreach ($p in $selectedChromeProcesses) { ... }
```

## Unsaved Work Detection

The function checks VS Code window titles for unsaved work indicators:

```powershell
$hasUnsavedWork = $false
foreach ($proc in $codeHits) {
  if ($proc.Context -like "*UNSAVED WORK*") {
    $hasUnsavedWork = $true
  }
}

if ($hasUnsavedWork) {
  Write-Host "⚠ UNSAVED WORK DETECTED - Files may not be saved!" -ForegroundColor Red
}
```

This relies on the `Get-SmartProcessContext` function which detects `•` or `*` in window titles.

## Benefits

### User Experience
- ✅ **Prevents accidental data loss** - Separate confirmation for VS Code
- ✅ **Clear visibility** - Shows workspace names and unsaved work warnings
- ✅ **Flexible control** - Can keep VS Code while killing everything else
- ✅ **No surprises** - Always know exactly what you're agreeing to kill

### Developer Workflow
- ✅ **Preserves work in progress** - Can keep VS Code open while gaming
- ✅ **Quick context switching** - Easy to see what workspaces are open
- ✅ **Safety net** - Unsaved work detection prevents mistakes

### Gaming Optimization
- ✅ **Optional** - Can choose to kill VS Code for maximum RAM/CPU
- ✅ **Selective** - Can kill Chrome but keep VS Code (or vice versa)
- ✅ **Transparent** - Shows exactly how much RAM will be freed

## Example Session

```powershell
PS> .\run-sanity.bat -Profile gaming

=== CHROME BROWSER PROCESSES ===
Found 15 Chrome processes consuming 1,234.56 MB total
...
Kill ALL Chrome processes? [y/N] y
✓ Chrome will be terminated

=== VS CODE EDITOR PROCESSES ===
Found 8 VS Code processes consuming 543.21 MB total

Main Editor Process:
Name      PID    RAMMB        Context
----      ---    -----        -------
Code.exe  5678   234.56 MB   (workspace: system-sanity)

+ 7 helper/extension processes

Open workspaces:
  - system-sanity

This will close ALL VS Code processes (including all windows and extensions).
Kill ALL VS Code processes? [y/N] n
VS Code processes were skipped by user choice.

Proceed with service changes and process termination (other processes)? [Y/n] y
✓ Services and other processes will be terminated

=== EXECUTING SERVICE CHANGES ===
...

=== EXECUTING PROCESS TERMINATION ===
Terminating 17 total processes (10 other, 0 VS Code, 7 Chrome)...

[10 other processes terminated]
VS Code processes were skipped by user choice.
[7 Chrome processes terminated]

Process termination complete: 17 processes killed
```

## Related Features

### Chrome Decision Flow
- **CHROME-DECISION-FLOW.md** - Chrome separation (already existed)
- Now VS Code follows the same pattern!

### Process Context Detection
- `Get-SmartProcessContext` function detects:
  - VS Code workspaces
  - Unsaved work indicators
  - Document names
  - Server ports
- This context is used in the confirmation prompts

## Compatibility

This change maintains backward compatibility with:
- All existing flags (`-DryRun`, `-ForceChrome`, etc.)
- Profile configurations in `profiles.json`
- All other process handling logic

The only change is that VS Code processes now get their own confirmation step, preventing accidental termination of work in progress! 🎯
