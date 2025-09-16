# Enhanced Profile System with Interactive Prompts

## Overview

The profile system has been enhanced to support interactive prompts as part of the profile metadata definition. This addresses the user's request to move the hardcoded interactive prompt sections into the profile schema, making the system more flexible and configurable.

## Enhanced Profile Schema

### New `InteractivePrompts` Section

Each profile can now include an `InteractivePrompts` section that defines which services should prompt the user for configuration:

```json
{
  "profileName": {
    "StopServicesPre": [...],
    "KillProcesses": [...],
    "StartServicesPost": [...],
    "LaunchAppsPost": [...],
    "InteractivePrompts": {
      "serviceTag": {
        "enabled": true,
        "title": "Service Display Name",
        "description": "Detailed description of what this service does",
        "question": "Custom question to ask the user (optional)",
        "defaultNeeded": true
      }
    }
  }
}
```

### Interactive Prompt Configuration Fields

- **`enabled`**: Boolean indicating whether this prompt should be shown
- **`title`**: Display name for the service category
- **`description`**: Detailed explanation of what the service does
- **`question`**: Custom question to ask the user (optional - defaults to generic question)
- **`defaultNeeded`**: Default value if user doesn't provide input

## Supported Service Tags

The system supports the following service tags for interactive prompts:

- **`network`**: WiFi, network management, DHCP, DNS cache, network location awareness
- **`audio`**: Audio services and audio device management
- **`bluetooth`**: Bluetooth support services
- **`ui`**: Theme and user interface services
- **`storage-opt`**: Disk defragmentation, volume shadow copy services
- **`telemetry`**: Diagnostic and telemetry services

## Profile Examples

### Normal Profile
```json
{
  "normal": {
    "InteractivePrompts": {
      "network": {
        "enabled": true,
        "title": "Network Services",
        "description": "These services manage your network connections and internet access.",
        "question": "Do you need network services for normal use? (y/N)",
        "defaultNeeded": true
      },
      "audio": {
        "enabled": true,
        "title": "Audio Services",
        "description": "These services manage audio playback and recording.",
        "question": "Do you need audio services for normal use? (y/N)",
        "defaultNeeded": true
      },
      "bluetooth": {
        "enabled": true,
        "title": "Bluetooth Services",
        "description": "These services manage Bluetooth devices and connections.",
        "question": "Do you need Bluetooth services for normal use? (y/N)",
        "defaultNeeded": false
      }
    }
  }
}
```

### Gaming Profile
```json
{
  "gaming": {
    "InteractivePrompts": {
      "audio": {
        "enabled": true,
        "title": "Audio Services",
        "description": "These services manage audio playback and recording.",
        "question": "Do you need audio services for gaming? (y/N)",
        "defaultNeeded": true
      },
      "network": {
        "enabled": true,
        "title": "Network Services",
        "description": "These services manage your network connections and internet access.",
        "question": "Do you need network services for gaming? (y/N)",
        "defaultNeeded": true
      }
    }
  }
}
```

### Development Profile
```json
{
  "dev": {
    "InteractivePrompts": {
      "network": {
        "enabled": true,
        "title": "Network Services",
        "description": "These services manage your network connections and internet access.",
        "question": "Do you need network services for development? (y/N)",
        "defaultNeeded": true
      },
      "storage-opt": {
        "enabled": true,
        "title": "Storage Optimization Services",
        "description": "These services help optimize disk performance and defragment storage.",
        "question": "Do you need storage optimization for development? (y/N)",
        "defaultNeeded": false
      },
      "telemetry": {
        "enabled": true,
        "title": "Diagnostic/Telemetry Services",
        "description": "These services help Windows diagnose issues and provide feedback.",
        "question": "Do you want to keep diagnostic services for development? (y/N)",
        "defaultNeeded": false
      }
    }
  }
}
```

## Usage

### Direct Service Assessment
```powershell
# Interactive mode for any profile - prompts user based on profile configuration
powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractivePrompts
powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode gaming -InteractivePrompts
powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode dev -InteractivePrompts
```

### Through Main System Script
```powershell
# Run service assessment with interactive prompts based on profile configuration
powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile normal -ServiceAssess -ServiceInteractivePrompts
powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile gaming -ServiceAssess -ServiceInteractivePrompts
powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile dev -ServiceAssess -ServiceInteractivePrompts
```

## User Experience

When running in interactive mode, users will see prompts configured by the profile:

```
Interactive Service Configuration for 'normal' Mode
=================================================
Configure which services you want to keep running for this mode:

Network Services:
  These services manage your network connections and internet access.
Do you need network services for normal use? (y/N)

Audio Services:
  These services manage audio playback and recording.
Do you need audio services for normal use? (y/N)

Bluetooth Services:
  These services manage Bluetooth devices and connections.
Do you need Bluetooth services for normal use? (y/N)
```

## Benefits

1. **Profile-Specific Configuration**: Each profile can have different interactive prompts tailored to its use case
2. **Flexible Schema**: Easy to add new service types or modify existing ones
3. **Customizable Questions**: Each profile can have custom questions and descriptions
4. **Default Values**: Profiles can specify sensible defaults for each service type
5. **Backward Compatibility**: Profiles without InteractivePrompts work as before
6. **Extensible**: Easy to add new service tags and prompt types

## Implementation Details

### Key Changes Made

1. **Enhanced Profile Schema**: Added `InteractivePrompts` section to profiles.json
2. **Refactored Interactive Logic**: Moved from hardcoded sections to profile-driven prompts
3. **Updated Function Names**: Changed from `Get-UserPreferencesForNormal` to `Get-UserPreferencesFromProfile`
4. **Parameter Renaming**: Changed from `-InteractiveNormal` to `-InteractivePrompts` to reflect broader applicability
5. **Profile Loading**: Added profile configuration loading in the assessment script
6. **Default Handling**: Enhanced logic to use profile defaults when user preferences aren't available

### Files Modified

1. **`profiles.json`** - Enhanced with InteractivePrompts metadata for all profiles
2. **`assess_services.ps1`** - Refactored to use profile-based interactive prompts
3. **`system-sanity.ps1`** - Updated parameter names and integration
4. **`test_enhanced_profiles.ps1`** - Test script for the enhanced system
5. **`ENHANCED_PROFILE_SYSTEM.md`** - This documentation

## Future Enhancements

The enhanced profile system provides a foundation for:

1. **Conditional Prompts**: Prompts that only show under certain conditions
2. **Profile Inheritance**: Base profiles that other profiles can extend
3. **User Preference Persistence**: Saving user choices across runs
4. **Advanced Service Dependencies**: Prompts that consider service relationships
5. **Custom Service Tags**: User-defined service categories and prompts

This implementation successfully addresses the user's request to move interactive prompt configuration into the profile metadata, making the system more flexible and maintainable.