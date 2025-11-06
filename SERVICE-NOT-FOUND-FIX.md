# Service Not Found Warning Fix - November 4, 2025

## Problem

The script was showing warnings for services that don't exist on the system:

```
WARNING: Could not stop service SQLSERVERAGENT : Cannot find any service with service name 'SQLSERVERAGENT'.
WARNING: Could not stop service MSSQLSERVER : Cannot find any service with service name 'MSSQLSERVER'.
WARNING: Could not stop service gupdate : Cannot find any service with service name 'gupdate'.
WARNING: Could not stop service gupdatem : Cannot find any service with service name 'gupdatem'.
```

## Root Cause

The `profiles.json` includes services that may not be installed on every system:
- **MSSQLSERVER/SQLSERVERAGENT** - Only exist if SQL Server is installed
- **gupdate/gupdatem** - Only exist if Google Chrome/Update is installed
- **AdobeARMservice** - Only exists if Adobe Reader/Acrobat is installed
- **DbxSvc** - Only exists if Dropbox is installed

The old code tried to stop every service in the list, even if it didn't exist, causing warnings.

## Solution

Updated `Stop-ServicesInOrder` and `Start-ServicesInOrder` functions to:

1. **Check if service exists** before attempting to stop/start it
2. **Silently skip** non-existent services (no warning)
3. **Support wildcards** (e.g., `OneSyncSvc*`) to handle multiple service instances

### Before:
```powershell
$s = Get-Service -Name $svc -ErrorAction Stop
if ($s.Status -ne 'Stopped') {
  Stop-Service -Name $svc -Force
}
```
**Problem:** Throws exception if service doesn't exist, shows warning

### After:
```powershell
$matchingServices = Get-Service -Name $svc -ErrorAction SilentlyContinue
if (-not $matchingServices) {
  # Service doesn't exist on this system - skip silently
  continue
}

foreach ($service in @($matchingServices)) {
  if ($service.Status -ne 'Stopped') {
    Stop-Service -Name $service.Name -Force
  }
}
```
**Benefit:** Silently skips non-existent services, handles wildcards

## What Changed

### Stop-ServicesInOrder Function:
1. Changed `Get-Service -ErrorAction Stop` → `Get-Service -ErrorAction SilentlyContinue`
2. Added check: `if (-not $matchingServices) { continue }`
3. Added foreach loop to handle wildcard matches (e.g., `OneSyncSvc*` → `OneSyncSvc_1234`, `OneSyncSvc_5678`)

### Start-ServicesInOrder Function:
1. Same changes as Stop function
2. Ensures consistent behavior for service start/stop

## Benefits

### User Experience:
- ✅ **No more warnings** for services you don't have installed
- ✅ **Cleaner output** - only shows actual actions taken
- ✅ **Wildcard support** - handles services with dynamic names (OneSyncSvc, CDPUserSvc, etc.)

### System Compatibility:
- ✅ **Works on all systems** - whether you have SQL Server, Chrome, Adobe, Dropbox or not
- ✅ **Profile flexibility** - can include optional services without breaking systems that don't have them
- ✅ **Future-proof** - adding new services to profiles.json won't break systems without them

## Wildcard Services

These services use wildcards because they have dynamic names:

### OneSyncSvc*
- **Actual names**: `OneSyncSvc_402c8`, `OneSyncSvc_Session1`, etc.
- **Purpose**: OneDrive sync service per user session
- **Why wildcard**: Service name includes unique user/session ID

### CDPUserSvc*
- **Actual names**: `CDPUserSvc_402c8`, `CDPUserSvc_123ab`, etc.
- **Purpose**: Connected Devices Platform User Service
- **Why wildcard**: Service name includes unique user ID

The updated code now properly handles these:
```powershell
# profiles.json includes: "OneSyncSvc*"
# Script finds: OneSyncSvc_402c8, OneSyncSvc_Session1
# Result: Stops both instances
```

## Example Output

### Before (noisy):
```
=== SERVICE RECOMMENDATIONS ===
No unneeded or mode-specific services are currently running.

WARNING: Could not stop service SQLSERVERAGENT : Cannot find...
WARNING: Could not stop service MSSQLSERVER : Cannot find...
WARNING: Could not stop service gupdate : Cannot find...
WARNING: Could not stop service gupdatem : Cannot find...
```

### After (clean):
```
=== SERVICE RECOMMENDATIONS ===
No unneeded or mode-specific services are currently running.

Stopping service: DiagTrack
Stopping service: WSearch
Stopping service: OneSyncSvc_402c8
```

Only shows services that actually exist and are being stopped!

## Testing

To verify the fix works:

### Test 1: System WITHOUT SQL Server
```powershell
.\run-sanity.bat -Profile gaming
# Should NOT show warnings about SQLSERVERAGENT or MSSQLSERVER
```

### Test 2: System WITHOUT Google Update
```powershell
.\run-sanity.bat -Profile gaming
# Should NOT show warnings about gupdate or gupdatem
```

### Test 3: System WITH wildcard services
```powershell
Get-Service OneSyncSvc* | Select-Object Name, Status
# Shows: OneSyncSvc_402c8 (Running)

.\run-sanity.bat -Profile gaming
# Should show: "Stopping service: OneSyncSvc_402c8"
```

## Related Changes

This fix complements the earlier change to use service stops instead of process kills:
- **SERVICE-vs-PROCESS-OPTIMIZATION.md** - Why we stop services
- **This fix** - How we stop services (gracefully, with existence checks)

Together, these ensure:
1. Services are stopped instead of processes (cleaner)
2. Non-existent services are skipped silently (no errors)
3. Wildcard services are handled properly (flexibility)
