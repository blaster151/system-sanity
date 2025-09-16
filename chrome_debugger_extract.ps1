# Proof-of-concept: Chrome PID mapping via remote debugging
# Enhanced with retry logic and error handling

Write-Host "Starting Chrome with remote debugging enabled..." -ForegroundColor Green

# Start Chrome with debugging port
$chromeProcess = Start-Process "chrome.exe" -ArgumentList "--remote-debugging-port=9222" -PassThru -NoNewWindow

if (-not $chromeProcess) {
    Write-Error "Failed to start Chrome process"
    exit 1
}

Write-Host "Chrome started with PID: $($chromeProcess.Id)" -ForegroundColor Yellow

# Function to test if Chrome debugging port is ready
function Test-ChromeDebugPort {
    param([int]$Port = 9222)
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$Port/json" -TimeoutSec 5 -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Wait for Chrome debugging port to be ready with retry logic
$maxRetries = 12  # Total wait time: up to 60 seconds
$retryCount = 0
$baseDelay = 2

Write-Host "Waiting for Chrome debugging port to be ready..." -ForegroundColor Yellow

do {
    $retryCount++
    $delay = [Math]::Min($baseDelay * $retryCount, 10)  # Exponential backoff, max 10 seconds
    
    Write-Host "Attempt $retryCount/$maxRetries - waiting $delay seconds..." -ForegroundColor Cyan
    
    Start-Sleep -Seconds $delay
    
    if (Test-ChromeDebugPort) {
        Write-Host "Chrome debugging port is ready!" -ForegroundColor Green
        break
    }
    
    # Check if Chrome process is still running
    if ($chromeProcess.HasExited) {
        Write-Error "Chrome process exited unexpectedly. Exit code: $($chromeProcess.ExitCode)"
        exit 1
    }
    
} while ($retryCount -lt $maxRetries)

if ($retryCount -ge $maxRetries) {
    Write-Error "Chrome debugging port failed to become ready after $maxRetries attempts"
    Write-Host "This could be due to:" -ForegroundColor Yellow
    Write-Host "  - Chrome taking longer than expected to start" -ForegroundColor Yellow
    Write-Host "  - Port 9222 being blocked or in use" -ForegroundColor Yellow
    Write-Host "  - Chrome security settings preventing remote debugging" -ForegroundColor Yellow
    Write-Host "  - Antivirus software blocking the connection" -ForegroundColor Yellow
    exit 1
}

# Now attempt to get the debugging information
Write-Host "Retrieving Chrome tab information..." -ForegroundColor Green

try {
    $response = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 10
    
    if ($response -and $response.Count -gt 0) {
        Write-Host "Found $($response.Count) Chrome tabs/processes" -ForegroundColor Green
        
        $chromeData = $response | ForEach-Object {
            [PSCustomObject]@{
                Title = $_.title
                URL   = $_.url
                Type  = $_.type
                PID   = if ($_.webSocketDebuggerUrl) { 
                    # Extract PID from webSocketDebuggerUrl if available
                    if ($_.webSocketDebuggerUrl -match 'ws://[^/]+/(\d+)') { 
                        $matches[1] 
                    } else { 
                        "N/A" 
                    }
                } else { 
                    "N/A" 
                }
                WebSocketUrl = $_.webSocketDebuggerUrl
            }
        }
        
        $chromeData | Export-Csv -Path "chrome-tab-map.csv" -NoTypeInformation
        Write-Host "Chrome tab mapping saved to: chrome-tab-map.csv" -ForegroundColor Green
        
        # Display summary
        $chromeData | Format-Table -AutoSize
    }
    else {
        Write-Warning "No Chrome tabs or processes found via debugging API"
    }
}
catch {
    Write-Error "Failed to retrieve Chrome debugging information: $($_.Exception.Message)"
    Write-Host "Chrome may not be running with debugging enabled, or the connection was refused." -ForegroundColor Yellow
    exit 1
}

Write-Host "Chrome debugging extraction completed successfully!" -ForegroundColor Green
