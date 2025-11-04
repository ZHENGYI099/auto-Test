# Wrapper script to run test with visible output
# This script will stay open even if the test fails

$TestScript = "$PSScriptRoot\output\test_case1test_v2.ps1"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Test Runner - Auto-Test V2" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[FAIL] Not running as Administrator!" -ForegroundColor Red
    Write-Host "Restarting as Administrator..." -ForegroundColor Yellow
    
    # Restart as admin
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "[PASS] Running as Administrator" -ForegroundColor Green
Write-Host "[INFO] Test Script: $TestScript" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path $TestScript)) {
    Write-Host "[FAIL] Test script not found: $TestScript" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

# Run the test script
Write-Host "[START] Starting test execution..." -ForegroundColor Cyan
Write-Host ""

try {
    & $TestScript
    $exitCode = $LASTEXITCODE
    
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "Test completed with exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
    Write-Host "======================================" -ForegroundColor Cyan
} catch {
    Write-Host ""
    Write-Host "❌ Exception occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
