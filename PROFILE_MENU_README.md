# Profile Menu Feature

## Overview
The `system-sanity.ps1` script now includes an interactive profile menu that appears when no profile is specified via the `-Profile` parameter.

## How It Works

### When the Menu Appears
- The menu is displayed when you run the script without specifying a `-Profile` parameter
- Example: `powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1`

### When the Menu is Bypassed
- The menu is skipped when you specify a profile directly
- Example: `powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile gaming`

### Menu Options
The menu displays:
1. **Available Profiles** - Each profile shows a brief description of what it does:
   - Number of process types it will kill
   - Number of services it will stop
   - Number of apps it will launch
2. **Skip Profile Selection** - Use the default junk-kill list (same as before)
3. **Exit** - Exit the script without proceeding

### Example Menu Output
```
Available Profiles:
==================
1. dev           - Kills 4 process types, Launches 2 apps
2. gaming        - Kills 6 process types, Stops 2 services, Launches 1 apps
3. normal        - Kills 2 process types

4. Skip profile selection (use default junk-kill list)
5. Exit

Select a profile (1-5): 
```

## Benefits
- **User-Friendly**: No need to remember profile names or use `-ListProfiles` first
- **Informative**: Each profile shows what it will do before selection
- **Flexible**: Still supports command-line profile specification for automation
- **Safe**: Option to exit or use default behavior if unsure

## Backward Compatibility
- All existing command-line usage continues to work unchanged
- The `-ListProfiles` parameter still works as before
- Scripts that specify profiles directly are unaffected