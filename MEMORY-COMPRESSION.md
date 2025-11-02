# Chrome Batching & Memory Compression Management - November 1, 2025

## Changes Made

### 1. Improved Chrome Process Confirmation

**Before:**
- Chrome processes went through individual permission prompts
- No clear summary of what would be killed
- Difficult to see total resource impact

**After:**
- **Single Y/N prompt for ALL Chrome processes together**
- Shows clear summary with total memory usage
- Groups processes by type (main browser vs renderers/tabs)
- Clear warning that ALL tabs and extensions will be closed

**Example Output:**
```
=== CHROME BROWSER PROCESSES ===
Found 15 Chrome processes consuming 1,234.56 MB total

Main Browser Processes:
Name        PID    RAMMB        Context
----        ---    -----        -------
chrome.exe  1234   543.21 MB   (browser)
chrome.exe  5678   234.56 MB   (browser with tabs)

+ 13 renderer/tab processes

This will close ALL Chrome processes (including all tabs and extensions).
Kill ALL Chrome processes? [y/N]
```

### 2. Memory Compression Management

**What is Memory Compression?**
- Windows feature that compresses inactive memory pages to reduce RAM usage
- **Trade-off**: Saves RAM but uses CPU cycles for compression/decompression
- Can cause performance spikes and stuttering during gameplay

**New Feature:**
- Automatically offers to disable Memory Compression when using gaming profile
- Tracks as permanent change (persists until re-enabled)
- Can be manually controlled

**Gaming Profile Behavior:**
When running `.\run-sanity.bat -Profile gaming`, the script will:
1. Check current Memory Compression status
2. Offer to disable it (with explanation)
3. Track the change for later reversal if desired

**Example Output:**
```
=== MEMORY COMPRESSION MANAGEMENT ===
Current Memory Compression Status: ENABLED

Disabling Memory Compression...
Note: This can improve gaming performance by reducing CPU overhead from compression.
✓ Memory Compression disabled successfully
  This setting persists until re-enabled or system restart.
```

## Why Disable Memory Compression for Gaming?

**Problems During Gameplay:**
1. **Stuttering**: Compression/decompression happens in background
2. **CPU Spikes**: Takes CPU cycles away from the game
3. **Unpredictable Performance**: Compression triggers at random times
4. **Frame Drops**: Can cause sudden FPS drops when memory is compressed/decompressed

**Benefits of Disabling:**
- More consistent frame rates
- Lower CPU overhead
- Eliminates random performance spikes
- Better for systems with adequate RAM (8GB+)

**When to Keep It Enabled:**
- Low RAM systems (< 8GB)
- Normal desktop use (non-gaming)
- When running many applications simultaneously

## Manual Control

### Disable Memory Compression
```powershell
Disable-MMAgent -MemoryCompression
```

### Enable Memory Compression
```powershell
Enable-MMAgent -MemoryCompression
```

### Check Status
```powershell
Get-MMAgent
```

## Technical Details

### Memory Compression Process
The "Memory Compression" process you see in Task Manager (`MemCompression`) is actually part of the `System` process:
- Runs as a thread in the System process
- Compresses memory pages that haven't been accessed recently
- Decompresses them when accessed again
- Uses Xpress compression algorithm

### Performance Impact
- **CPU Usage**: 5-15% during active compression
- **RAM Savings**: 20-40% reduction in physical RAM usage
- **Latency**: 50-200ms decompression overhead
- **Gaming Impact**: Can cause 10-30 FPS drops during compression events

## Usage Examples

### Gaming Session (Automatic)
```powershell
.\run-sanity.bat -Profile gaming
# Will prompt to disable Memory Compression
```

### Gaming Session (Force Disable, No Prompt)
```powershell
# Edit profiles.json to add DisableMemoryCompression flag
# Or run PowerShell directly:
Disable-MMAgent -MemoryCompression
.\run-sanity.bat -Profile gaming
```

### Re-enable After Gaming
```powershell
Enable-MMAgent -MemoryCompression
```

### Check What Was Changed
```powershell
.\run-sanity.bat -ShowChanges
```

## Revert Instructions

### If You Want Memory Compression Back
The script tracks the change in `out\permanent-changes.csv`. To revert:

**Option 1 - PowerShell:**
```powershell
Enable-MMAgent -MemoryCompression
```

**Option 2 - Via Script:**
```powershell
.\run-sanity.bat -ShowChanges
# Shows the revert command in the log
```

**Option 3 - Restart:**
Memory Compression settings persist across reboots, so you need to explicitly re-enable it if disabled.

## Other Profiles

### Dev Profile
Does **NOT** automatically disable Memory Compression (usually not needed for development work)

### Normal Profile  
Does **NOT** automatically disable Memory Compression (keeps normal Windows behavior)

## Notes

- Memory Compression settings require Administrator privileges
- Changes persist across reboots (not temporary like stopped services)
- Safe to enable/disable multiple times
- No data loss when disabling (just releases compressed memory)
- Windows 10/11 feature (not available on older Windows versions)

## Monitoring Memory Compression

### In Task Manager
- Open Task Manager → Performance → Memory
- Look for "Compressed memory" in the details
- If showing 0 MB, compression is disabled

### In Performance Monitor (perfmon)
- Counter: `\Memory\% Compressed Memory In Use`
- If always 0, compression is disabled

### In PowerShell
```powershell
Get-MMAgent | Format-List MemoryCompression
```

## Troubleshooting

### "Access Denied" Error
- Run PowerShell as Administrator
- Or run the script with elevated privileges

### Memory Compression Won't Disable
- Check if Group Policy is enforcing it
- Run: `gpedit.msc` → Computer Configuration → Administrative Templates → System → Memory Compression
- Set to "Not Configured" or "Disabled"

### Performance Still Poor After Disabling
Other potential culprits:
- SysMain (Superfetch) - disable with `Stop-Service SysMain`
- Windows Search - disable with `Stop-Service WSearch`
- Background Windows Update - disable with `Stop-Service wuauserv`
- All of these are in the gaming profile's StopServicesPre list!
