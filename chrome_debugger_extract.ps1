# chrome_debugger_extract.ps1
# Extract Chrome/Edge tab and extension information
# Can work with already-running browsers if they have remote debugging enabled

param(
    [int]$ChromePort = 9222,
    [int]$EdgePort = 9223,
    [string]$OutputPath = ".\out\browser-tabs.csv",
    [switch]$IncludeEdge
)

function Get-ChromeTabInfo {
    param([int]$Port)
    
    try {
        # Try primary endpoint first, then fall back to /json/list for newer Chrome versions
        $response = @()
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:$Port/json" -ErrorAction Stop -TimeoutSec 2
        } catch {
            $response = @()
        }
        if (-not $response -or $response.Count -eq 0) {
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:$Port/json/list" -ErrorAction Stop -TimeoutSec 2
            } catch {
                $response = @()
            }
        }
        
        $tabs = @()
        foreach ($item in $response) {
            # Try to extract process ID from WebSocket URL if available
            $pid = $null
            if ($item.webSocketDebuggerUrl -match "pid=(\d+)") {
                $pid = $matches[1]
            }
            
            # Determine what kind of Chrome component this is
            $componentType = "Unknown"
            $details = ""
            
            if ($item.type -eq "page") {
                if ($item.url -match "^chrome-extension://([^/]+)") {
                    $componentType = "Extension"
                    $extensionId = $matches[1]
                    $details = "Extension ID: $extensionId"
                } elseif ($item.url -match "^chrome://") {
                    $componentType = "Chrome Internal"
                    $details = $item.url
                } elseif ($item.url -match "^edge://") {
                    $componentType = "Edge Internal"
                    $details = $item.url
                } elseif ($item.url -and $item.url -ne "about:blank") {
                    $componentType = "Web Page"
                    # Extract domain from URL
                    if ($item.url -match "^https?://([^/]+)") {
                        $details = "Domain: $($matches[1])"
                    }
                } else {
                    $componentType = "Blank Tab"
                }
            } elseif ($item.type -eq "background_page") {
                $componentType = "Extension Background"
                if ($item.url -match "chrome-extension://([^/]+)") {
                    $extensionId = $matches[1]
                    $details = "Extension ID: $extensionId"
                }
            } elseif ($item.type -eq "service_worker") {
                $componentType = "Service Worker"
            }
            
            $tabs += [PSCustomObject]@{
                Browser = if ($Port -eq 9222) { "Chrome" } else { "Edge" }
                Type = $componentType
                Title = if ($item.title) { $item.title } else { "(no title)" }
                URL = if ($item.url) { $item.url } else { "(no url)" }
                Details = $details
                ProcessID = $pid
                WebSocketURL = $item.webSocketDebuggerUrl
            }
        }
        
        return $tabs
    } catch {
        Write-Warning "Could not connect to browser on port $Port. Browser may not be running with remote debugging enabled."
        Write-Warning "To enable: Start Chrome/Edge with --remote-debugging-port=$Port"
        return @()
    }
}

function Get-BrowserProcessDetails {
    # Get all Chrome and Edge processes with command line info
    $browsers = @()
    
    # Chrome processes
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue
            $cmdLine = $proc.CommandLine
            
            $processType = "Chrome Main"
            if ($cmdLine -match "--type=([^\s]+)") {
                $processType = "Chrome: $($matches[1])"
            }
            
            $browsers += [PSCustomObject]@{
                Browser = "Chrome"
                ProcessName = $_.Name
                PID = $_.Id
                Type = $processType
                RAMMB = [math]::Round($_.WorkingSet64 / 1MB, 2)
                CommandLine = $cmdLine
            }
        } catch {
            # Ignore errors for processes we can't access
        }
    }
    
    # Edge processes
    Get-Process -Name "msedge" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue
            $cmdLine = $proc.CommandLine
            
            $processType = "Edge Main"
            if ($cmdLine -match "--type=([^\s]+)") {
                $processType = "Edge: $($matches[1])"
            }
            
            $browsers += [PSCustomObject]@{
                Browser = "Edge"
                ProcessName = $_.Name
                PID = $_.Id
                Type = $processType
                RAMMB = [math]::Round($_.WorkingSet64 / 1MB, 2)
                CommandLine = $cmdLine
            }
        } catch {
            # Ignore errors
        }
    }
    
    return $browsers
}

# Main execution
Write-Host "=== BROWSER DEBUGGING INFO EXTRACTOR ===" -ForegroundColor Cyan
Write-Host ""

# Get process details (always available)
Write-Host "Analyzing browser processes..." -ForegroundColor Yellow
$processDetails = Get-BrowserProcessDetails

if ($processDetails.Count -gt 0) {
    Write-Host "Found $($processDetails.Count) browser processes:" -ForegroundColor Green
    $processDetails | Sort-Object Browser, Type | Format-Table Browser, PID, Type, RAMMB -AutoSize
    
    # Export process details
    $processPath = $OutputPath -replace "\.csv$", "-processes.csv"
    $processDetails | Export-Csv -Path $processPath -NoTypeInformation
    Write-Host "Process details exported to: $processPath" -ForegroundColor Green
} else {
    Write-Host "No Chrome or Edge processes found." -ForegroundColor Gray
}

# Try to get tab information (requires remote debugging)
Write-Host ""
Write-Host "Attempting to extract tab/extension information..." -ForegroundColor Yellow

$allTabs = @()

# Try Chrome
$chromeTabs = Get-ChromeTabInfo -Port $ChromePort
if ($chromeTabs.Count -gt 0) {
    Write-Host "Found $($chromeTabs.Count) Chrome tabs/extensions" -ForegroundColor Green
    $allTabs += $chromeTabs
}

# Try Edge if requested
if ($IncludeEdge) {
    $edgeTabs = Get-ChromeTabInfo -Port $EdgePort
    if ($edgeTabs.Count -gt 0) {
        Write-Host "Found $($edgeTabs.Count) Edge tabs/extensions" -ForegroundColor Green
        $allTabs += $edgeTabs
    }
}

if ($allTabs.Count -gt 0) {
    Write-Host ""
    Write-Host "Tab/Extension Summary:" -ForegroundColor Cyan
    $allTabs | Format-Table Browser, Type, Title, Details -AutoSize
    
    # Export tab details
    $allTabs | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host ""
    Write-Host "Tab details exported to: $OutputPath" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "No tab information available. To enable:" -ForegroundColor Yellow
    Write-Host "  Chrome: Start with --remote-debugging-port=$ChromePort" -ForegroundColor Gray
    Write-Host "  Edge:   Start with --remote-debugging-port=$EdgePort" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== COMPLETED ===" -ForegroundColor Cyan
