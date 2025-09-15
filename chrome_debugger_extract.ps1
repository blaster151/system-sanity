# Proof-of-concept: Chrome PID mapping via remote debugging
Start-Process "chrome.exe" -ArgumentList "--remote-debugging-port=9222" -PassThru
Start-Sleep -Seconds 5

$response = Invoke-RestMethod -Uri "http://localhost:9222/json"

$response | ForEach-Object {
    [PSCustomObject]@{
        Title = $_.title
        URL   = $_.url
        Type  = $_.type
        PID   = $_.webSocketDebuggerUrl
    }
} | Export-Csv -Path "chrome-tab-map.csv" -NoTypeInformation
