@echo off
setlocal
pushd %~dp0
powershell.exe -ExecutionPolicy Bypass -File ".\system-sanity.ps1" %*
popd
endlocal

REM Usage examples:
REM run-sanity.bat
REM run-sanity.bat -ShowChanges
REM run-sanity.bat -Profile gaming -Apply -PromptEach
REM run-sanity.bat -CleanupSpace
