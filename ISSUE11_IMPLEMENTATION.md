# Issue 11 Implementation: Expanded "Needed for normal" Designation

## Problem Statement
Issue 11 requested expanding the "Needed for normal" designation to more services, with the suggestion to ask the user about things like "Do you need airplane mode?" (referring to network services).

## Solution Implemented

### 1. Enhanced Service Assessment Script (`assess_services.ps1`)

#### New Parameter
- Added `-InteractiveNormal` parameter to enable interactive prompts for additional "normal" services

#### New Functionality
- **Enhanced Service Tagging**: Added more comprehensive service tags including:
  - `network`: WiFi, network management, DHCP, DNS cache, network location awareness
  - `storage-opt`: Disk defragmentation, volume shadow copy services
  - `audio`: Audio services and audio device management
  - `bluetooth`: Bluetooth support services
  - `ui`: Theme and user interface services
  - `telemetry`: Diagnostic and telemetry services

- **Interactive User Prompts**: New `Get-UserPreferencesForNormal` function that prompts users about:
  - Network services (WiFi, network management, DHCP)
  - Storage optimization services
  - Audio services
  - Bluetooth services
  - UI/Theme services
  - Diagnostic/Telemetry services

- **Enhanced Opinion Matrix**: Updated `Get-Opinion` function to:
  - Accept user preferences as a parameter
  - Apply user preferences to determine if services are "Needed for normal"
  - Provide sensible defaults for each service type

### 2. Enhanced Main Script (`system-sanity.ps1`)

#### New Parameter
- Added `-ServiceInteractiveNormal` parameter to pass through to the service assessment script

#### Integration
- Updated service assessment call to pass the new parameter
- Added usage examples in help text

## Usage Examples

### Direct Service Assessment
```powershell
# Interactive mode for Normal profile - prompts user about additional services
powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractiveNormal

# With live service detection
powershell -ExecutionPolicy Bypass -File .\assess_services.ps1 -Mode normal -InteractiveNormal -Live
```

### Through Main System Script
```powershell
# Run service assessment with interactive prompts for additional "normal" services
powershell -ExecutionPolicy Bypass -File .\system-sanity.ps1 -Profile normal -ServiceAssess -ServiceInteractiveNormal
```

## User Experience

When running in interactive mode, users will see prompts like:

```
Additional Services for 'Normal' Mode
=====================================
Some services might be useful for normal daily use. Would you like to keep any of these running?

Network Services (WiFi, Network Management, DHCP):
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

1. **User Control**: Users can now specify which additional services they want to keep running for "normal" use
2. **Flexibility**: The system adapts to user preferences rather than using hardcoded assumptions
3. **Comprehensive Coverage**: Covers network, audio, Bluetooth, UI, and diagnostic services
4. **Backward Compatibility**: Existing functionality remains unchanged when not using the new parameter
5. **Clear Documentation**: Each service type is explained to help users make informed decisions

## Files Modified

1. `assess_services.ps1` - Main implementation of interactive prompts and enhanced service assessment
2. `system-sanity.ps1` - Integration of new parameter and usage examples
3. `test_issue11.ps1` - Test script to validate the implementation
4. `ISSUE11_IMPLEMENTATION.md` - This documentation

## Testing

A test script (`test_issue11.ps1`) has been created to validate the functionality. The implementation has been designed to be robust and handle edge cases gracefully.

## Future Enhancements

The framework is extensible and could be enhanced to include:
- More service types (e.g., security services, backup services)
- Profile-specific user preferences that persist across runs
- Integration with the main profile system for automatic service management