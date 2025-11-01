# Service Handling Fixes - November 1, 2025

## Issues Fixed

### 1. **"Processing" Non-Existent Services**
**Problem**: Script was showing "Processing XYZ Service..." for services that don't exist on the system, causing confusion.

**Fix**: 
- Now verifies service actually exists with `Get-Service` before adding to action list
- Only processes services that are:
  - Actually present on the system
  - Currently running
  - Have actions to perform (startup type change or stop)

**Result**: Only real, actionable services are shown in the output.

### 2. **Mode-Specific Services Not Actionable**
**Problem**: Services listed as "not needed for {mode} mode" were shown but no option was given to actually stop them.

**Fix**:
- Combined both "unneeded generally" and "mode-specific" services into a single actionable list
- Both types of services now appear in the "=== SERVICE ACTIONS ===" section
- Users can choose to stop mode-specific services just like unneeded services

### 3. **Improved Service Action Output**
**Before**:
```
[1/10] Processing Adobe Acrobat Update Service...
[2/10] Processing AdobeUpdateService...
[3/10] Processing Fax...
```
(No indication of what happened or if service even exists)

**After**:
```
=== EXECUTING SERVICE CHANGES ===
Applying 3 service changes...

[1/3] Xbox Live Auth Manager [XblAuthManager]...
  ✓ Stopped service
  
[2/3] Windows Search [WSearch]...
  ✓ Set startup type to Manual
  ✓ Stopped service

Service changes complete: 2 successful, 0 failed
```

### 4. **Better Non-Interactive Behavior**
**Changed**: By default (non-interactive mode), script now:
- ✅ **DOES** stop running unneeded/mode-specific services
- ❌ **DOES NOT** change startup types (requires explicit user permission with `-ServicePromptEach`)

**Rationale**: Stopping a service is temporary (it restarts on reboot). Changing startup type is permanent and requires conscious user decision.

## Usage

### See Recommendations Only (No Changes)
```powershell
.\run-sanity.bat -DryRun
```

### Stop Recommended Services (No Startup Type Changes)
```powershell
.\run-sanity.bat -Profile gaming
```

### Stop Services AND Change Startup Types (Prompted for Each)
```powershell
.\run-sanity.bat -Profile gaming -ServicePromptEach
```

### Assess Services with Detailed Recommendations
```powershell
.\run-sanity.bat -Profile gaming -ServiceAssess
```

## Service Categories

### "Unneeded Generally"
Services that are rarely needed by anyone:
- Fax
- Remote Registry
- Retail Demo Service
- Diagnostic/Telemetry services

**Action**: Can be set to Manual startup and stopped

### "Not Needed for {Mode}"
Services useful in other modes but not the current one:

**Gaming Mode** might not need:
- SQL Server (development database)
- IIS (web server)
- Docker
- Hyper-V

**Dev Mode** might not need:
- Xbox services
- Gaming platform services

**Normal Mode** might not need:
- Windows Search (when not actively searching)
- Windows Update (when not actively updating)

**Action**: Can be stopped for current session (will restart on reboot)

## Examples

### Gaming Profile - What Gets Stopped
```
Services not needed for gaming mode:
  MSSQLSERVER                    [MSSQLSERVER] - SQL Server Database Engine (RAM: 245 MB)
  SQLSERVERAGENT                 [SQLSERVERAGENT] - SQL Server Agent (RAM: 89 MB)
  W3SVC                          [W3SVC] - IIS Web Server
  XblAuthManager                 [XblAuthManager] - Xbox Live Auth Manager
  XblGameSave                    [XblGameSave] - Xbox Live Game Save

=== SERVICE ACTIONS ===
Found 3 running services that can be optimized.

Prepared 3 service actions.

Proceed with service changes and process termination? [Y/n] y

=== EXECUTING SERVICE CHANGES ===
Applying 3 service changes...

[1/3] SQL Server (MSSQLSERVER) [MSSQLSERVER]...
  ✓ Stopped service
  
[2/3] SQL Server Agent (SQLSERVERAGENT) [SQLSERVERAGENT]...
  ✓ Stopped service
  
[3/3] Xbox Live Auth Manager [XblAuthManager]...
  ✓ Stopped service

Service changes complete: 3 successful, 0 failed
```

## Technical Details

### Service Filtering Logic
```powershell
# Only consider services that are:
1. In the recommended list (unneeded or mode-specific)
2. Actually present on the system (Get-Service succeeds)
3. Currently running (State = "Running")
4. Have actionable changes (startup type or stop)
```

### Service Verification
```powershell
$actualService = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if (-not $actualService) {
  # Service doesn't exist, skip it
  continue
}
```

This prevents attempting to modify services that:
- Don't exist on this Windows edition
- Were uninstalled by user
- Have different names on this system

## Benefits

1. **Clearer Output** - Only shows services that actually exist and will be modified
2. **Better UX** - All recommended services (both unneeded and mode-specific) are actionable
3. **Safer** - Doesn't change startup types by default (prevents accidental permanent changes)
4. **More Informative** - Clear success/failure indicators with color coding
5. **Accurate Counts** - Service count matches actual services processed
