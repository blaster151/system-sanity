# Chrome Decision Flow Separation - November 1, 2025

## Problem
Chrome processes were being bundled with the general "Proceed with service changes and process termination?" prompt, making it confusing whether the user was agreeing to kill Chrome or just other processes.

## Solution
Chrome processes now have their own **completely separate** decision point that happens BEFORE the main confirmation.

## New Flow

### Step 1: Chrome Decision (First)
```
=== CHROME BROWSER PROCESSES ===
Found 15 Chrome processes consuming 1,234.56 MB total

Main Browser Processes:
Name        PID    RAMMB        Context
----        ---    -----        -------
chrome.exe  1234   543.21 MB   (browser)

+ 13 renderer/tab processes

This will close ALL Chrome processes (including all tabs and extensions).
Kill ALL Chrome processes? [y/N]
```

**User Decision:** 
- `y` = Chrome will be killed
- `n` or Enter = Chrome will be skipped (preserved)

### Step 2: Everything Else (Second)
```
Proceed with service changes and process termination (non-Chrome processes)? [Y/n]
```

**User Decision:**
- `Y` or Enter = Kill other processes, stop services
- `n` = Skip everything else

### Step 3: Execution
```
=== EXECUTING PROCESS TERMINATION ===
Terminating 20 total processes (5 non-Chrome, 15 Chrome)...

[1/5] Terminating msedgewebview2.exe (PID: 1234)...
  ✓ Terminated msedgewebview2.exe (PID: 1234)
...

Terminating 15 Chrome processes...
[1/15] Terminating Chrome chrome.exe (PID: 5678)...
  ✓ Terminated chrome.exe (PID: 5678)
...
```

## Scenarios

### Scenario 1: Kill Chrome, Kill Others
```
Kill ALL Chrome processes? [y/N] y
Proceed with service changes and process termination (non-Chrome processes)? [Y/n] y
```
**Result:** Everything gets killed

### Scenario 2: Keep Chrome, Kill Others
```
Kill ALL Chrome processes? [y/N] n
Proceed with service changes and process termination (non-Chrome processes)? [Y/n] y
```
**Result:** Chrome stays running, other processes get killed

### Scenario 3: Kill Chrome, Keep Others
```
Kill ALL Chrome processes? [y/N] y
Proceed with service changes and process termination (non-Chrome processes)? [Y/n] n
```
**Result:** Only Chrome gets killed, everything else stays

### Scenario 4: Keep Everything
```
Kill ALL Chrome processes? [y/N] n
Proceed with service changes and process termination (non-Chrome processes)? [Y/n] n
```
**Result:** Nothing gets killed

## Technical Changes

### Before
1. Build combined list of all processes to kill
2. Ask: "Proceed with service changes and process termination?"
3. If yes, handle Chrome separately with Confirm-KillChrome
4. Kill everything

**Problem:** User already said "yes" to killing Chrome in step 2, then got asked again in step 3.

### After
1. Separate Chrome processes from non-Chrome processes
2. Ask: "Kill ALL Chrome processes?" (Chrome-specific)
3. Ask: "Proceed with service changes and process termination (non-Chrome)?" (Everything else)
4. Kill approved Chrome processes
5. Kill approved non-Chrome processes

**Benefit:** Two separate, clear decisions. No confusion.

## Code Structure

```powershell
# Step 1: Separate Chrome from everything else
$chromeProcesses = $plannedKills | Where-Object { $_.Name -like "chrome*" }
$nonChromeProcesses = $plannedKills | Where-Object { $_.Name -notlike "chrome*" }

# Step 2: Chrome decision (first)
$selectedChromeProcesses = @()
if ($chromeProcesses.Count -gt 0) {
  $okToKillChrome = Confirm-KillChrome -Planned $chromeProcesses
  if ($okToKillChrome) {
    $selectedChromeProcesses = $chromeProcesses
  }
}

# Step 3: Non-Chrome decision (second)
$selectedToKill = @()
if ($nonChromeProcesses.Count -gt 0) {
  $confirm = Read-Host "Proceed with service changes and process termination (non-Chrome)? [Y/n]"
  if ($confirm -notmatch '^(n|no)$') {
    # ... process selection logic ...
    $selectedToKill = # approved non-Chrome processes
  }
}

# Step 4: Execute (separate lists)
# Kill non-Chrome processes
foreach ($p in $selectedToKill) { ... }

# Kill Chrome processes
foreach ($p in $selectedChromeProcesses) { ... }
```

## Benefits

1. **Clear Intent**: User knows exactly what they're agreeing to
2. **Independent Decisions**: Can kill Chrome but keep other processes, or vice versa
3. **Better UX**: No confusion about what "yes" means
4. **Flexible**: Supports all combinations of user choices
5. **Transparent**: Shows Chrome count separately in execution output

## Example Session

```powershell
PS> .\run-sanity.bat -Profile gaming

=== PROCESS RECOMMENDATIONS ===
Processes matching kill patterns for gaming mode:
...
Total: 20 processes identified

=== CHROME BROWSER PROCESSES ===
Found 15 Chrome processes consuming 1,234.56 MB total
...
Kill ALL Chrome processes? [y/N] y
✓ Chrome will be terminated

Proceed with service changes and process termination (non-Chrome processes)? [Y/n] y
✓ Services and non-Chrome processes will be terminated

=== EXECUTING SERVICE CHANGES ===
...

=== EXECUTING PROCESS TERMINATION ===
Terminating 20 total processes (5 non-Chrome, 15 Chrome)...

[Non-Chrome processes]
[1/5] Terminating msedgewebview2.exe (PID: 1234)...
  ✓ Terminated
...

[Chrome processes]
Terminating 15 Chrome processes...
[1/15] Terminating Chrome chrome.exe (PID: 5678)...
  ✓ Terminated
...

Process termination complete: 20 processes killed
```

## Edge Cases Handled

### No Chrome Processes Found
- Chrome decision prompt is skipped
- Only shows non-Chrome prompt

### No Non-Chrome Processes Found
- Only shows Chrome decision prompt
- Skips non-Chrome prompt

### User Cancels Both
```
Kill ALL Chrome processes? [y/N] n
Chrome processes were skipped by user choice.

Proceed with service changes and process termination (non-Chrome processes)? [Y/n] n
Service changes and process termination cancelled by user.
```

### ForceChrome Flag
```powershell
.\run-sanity.bat -Profile gaming -ForceChrome
```
- Skips Chrome confirmation
- Chrome processes are automatically included
- Still asks about non-Chrome processes

## Related Flags

### -ForceChrome
Automatically approves Chrome killing without prompting

### -DryRun
Shows what would be killed but doesn't ask or execute

### -ServiceApply
Actually applies service changes (without this, just shows recommendations)

## Compatibility

This change maintains backward compatibility with:
- `-ForceChrome` flag (still works as expected)
- `-DryRun` mode (still shows everything without prompting)
- All existing profiles
- Chrome restoration with `-RestoreChrome`
