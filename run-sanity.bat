@echo off
setlocal
pushd %~dp0
powershell.exe -ExecutionPolicy Bypass -File ".\system-sanity.ps1" %*
popd
endlocal
