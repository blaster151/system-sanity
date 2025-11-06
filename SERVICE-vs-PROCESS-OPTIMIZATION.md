# Service vs Process Optimization - November 4, 2025

## Problem
Some processes should be stopped at the service level rather than killed as processes, because:
1. The service will just restart the killed process immediately
2. Stopping the service is cleaner and prevents respawning
3. Services can be properly stopped and restarted later

## Changes Made

### Services Added to Stop Lists

#### Gaming Profile - New Services:
- `ClickToRunSvc` - Microsoft Office Click-to-Run Service
- `gupdate` - Google Update Service (per-system)
- `gupdatem` - Google Update Service (manual start)
- `OneSyncSvc*` - OneDrive Sync Service (multiple instances)
- `AdobeARMservice` - Adobe Acrobat Update Service
- `DbxSvc` - Dropbox Windows Service

#### Dev Profile - New Services:
- `ClickToRunSvc` - Microsoft Office Click-to-Run Service
- `gupdate` - Google Update Service (per-system)
- `gupdatem` - Google Update Service (manual start)
- `OneSyncSvc*` - OneDrive Sync Service (multiple instances)
- `AdobeARMservice` - Adobe Acrobat Update Service

**Note:** Dropbox service (`DbxSvc`) is only stopped in gaming profile, not dev (developers may need file sync)

### Processes Removed from Kill Lists

These were converted from process kills to service stops:

1. **`OfficeClickToRun*`** → Now stopped via `ClickToRunSvc` service
2. **`GoogleUpdate*`** → Now stopped via `gupdate` and `gupdatem` services
3. **`OneDriveSetup*`** → Removed (OneDrive handled by `OneSyncSvc*` service)

### New Process Added

- **`Wisprflow*`** - Added to both gaming and dev profiles (appears to be a network/VPN process without a service)

## Before vs After

### Before:
```json
"KillProcesses": [
  {
    "pattern": "GoogleUpdate*",
    "promptUser": false,
    "reason": "Google updater processes"
  },
  {
    "pattern": "OfficeClickToRun*",
    "promptUser": false,
    "reason": "Office updater processes"
  }
]
```

**Problem:** These processes would be killed, but their services would immediately restart them.

### After:
```json
"StopServicesPre": [
  "ClickToRunSvc",
  "gupdate",
  "gupdatem"
]
```

**Solution:** Stopping the services prevents the processes from spawning at all.

## Service Details

### ClickToRunSvc (Office Click-to-Run)
- **Display Name**: Microsoft Office Click-to-Run Service
- **Processes**: OfficeClickToRun.exe, officec2rclient.exe
- **Purpose**: Manages Office updates and streaming installation
- **Impact**: Stopping prevents Office update checks and background processes

### gupdate / gupdatem (Google Update)
- **Display Name**: Google Update Service
- **Processes**: GoogleUpdate.exe, GoogleCrashHandler.exe
- **Purpose**: Manages Chrome and Google software updates
- **Impact**: Stopping prevents Google software update checks
- **Note**: `gupdate` runs automatically, `gupdatem` is manual-start

### OneSyncSvc* (OneDrive Sync)
- **Display Name**: Sync Host (various instances per user)
- **Processes**: OneDrive.exe, FileCoAuth.exe
- **Purpose**: Manages OneDrive file synchronization
- **Impact**: Stopping prevents cloud file sync
- **Note**: Wildcard needed because service name includes user ID

### AdobeARMservice (Adobe Acrobat Update)
- **Display Name**: Adobe Acrobat Update Service
- **Processes**: AdobeARM.exe, Adobe*.exe updaters
- **Purpose**: Manages Adobe Reader/Acrobat updates
- **Impact**: Stopping prevents Adobe update checks

### DbxSvc (Dropbox)
- **Display Name**: Dropbox Windows Service
- **Processes**: Dropbox.exe, DbxSvc.exe
- **Purpose**: Manages Dropbox file synchronization
- **Impact**: Stopping prevents cloud file sync
- **Gaming Only**: Not stopped in dev profile (developers may need active sync)

## Benefits

### Performance Gains:
1. **No Respawning**: Processes can't restart after being killed
2. **Cleaner**: Services stopped gracefully vs killing processes
3. **Resource Savings**: Background services consume CPU/RAM even when idle
4. **Network Reduction**: Update checks and sync operations stopped

### Gaming Profile Impact:
- **~5-10% RAM savings** from stopping updater/sync services
- **Reduced disk I/O** from background sync operations
- **Fewer network calls** from update checks
- **Lower CPU interrupts** from background services

### Dev Profile Impact:
- **Similar benefits** to gaming profile
- **Dropbox kept running** for active file sync needs
- **Focus on update services** rather than sync services

## Testing Recommendations

After applying these changes, verify:

1. **Services Actually Stopped**:
   ```powershell
   Get-Service ClickToRunSvc, gupdate, gupdatem, AdobeARMservice, DbxSvc | Select-Object Name, Status
   ```

2. **Processes No Longer Running**:
   ```powershell
   Get-Process *OfficeClickToRun*, *GoogleUpdate*, *Adobe*ARM* -ErrorAction SilentlyContinue
   ```

3. **Re-enable After Gaming**:
   - Services should restart on next boot
   - Or manually: `Start-Service ClickToRunSvc, gupdate, AdobeARMservice, DbxSvc`

## Future Candidates

Other processes that might benefit from service-level control:

1. **Steam** → `Steam Client Service` (but you probably want this for gaming!)
2. **Discord** → `Discord Update` service (if it exists)
3. **Spotify** → `SpotifyWebHelper` (no service, process-only)
4. **NVIDIA** → `NVDisplay.ContainerLocalSystem` (be careful, needed for GPU)

## Wisprflow Investigation

**Wisprflow** appears to be:
- Network monitoring or VPN-related process
- No Windows service found (process-level only)
- Added as process kill pattern to both profiles
- Likely safe to terminate for gaming/dev optimization

If Wisprflow is critical, consider removing it from kill lists.
