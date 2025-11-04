# ============================================================
# SETUP LOGGING
# ============================================================
$test_case_id = "case8test"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_${test_case_id}_$timestamp.log"

# Start transcript to capture all output
Start-Transcript -Path $logFile -Append

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST EXECUTION START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# PHASE 1: PRE-CHECK
# ============================================================
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

$script:SuccessCount = 0
$script:FailCount = 0

function Write-Result {
    param([string]$Msg, [bool]$Success)
    if ($Success -eq $true) {
        Write-Host "[PASS] $Msg" -ForegroundColor Green
        $script:SuccessCount++
    } else {
        Write-Host "[FAIL] $Msg" -ForegroundColor Red
        $script:FailCount++
    }
}

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[FAIL] ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "Running as Administrator" -Success $true
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$msiName = "cmdextension.msi"
# Service name mapping from context
$serviceName = "CloudManagedDesktopExtension"
# Log file path from scenario
$logFilePath = "$env:ProgramData\Microsoft\CMDExtension\Logs\CMDExtension.log"

# Check if MSI file exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed (by service existence)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service $serviceName already installed. Attempting uninstall before test." -Success $false
    # Attempt uninstall
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed successfully (exit code: $uninstallExitCode)" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (exit code: $uninstallExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
    Start-Sleep -Seconds 5
} else {
    Write-Result -Msg "No previous installation detected" -Success $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing $msiName silently..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=Test /qn"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProcess.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (exit code: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (exit code: 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges for installation (exit code: 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation returned unexpected exit code: $exitCode" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 10
$serviceObj = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceObj -and $serviceObj.Status -eq 'Running') {
    Write-Result -Msg "Service $serviceName is running after install" -Success $true
} else {
    Write-Result -Msg "Service $serviceName is NOT running after install" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying agent log file contents..." -ForegroundColor Cyan

# Check if log file exists
if (Test-Path $logFilePath) {
    Write-Result -Msg "Log file exists: $logFilePath" -Success $true
} else {
    Write-Result -Msg "Log file does NOT exist: $logFilePath" -Success $false
}

# Read log file and verify expected content
$expectedString = "Plugin run scheduler with CMDAgentCommunicationChannel:"
try {
    $logLines = Get-Content -Path $logFilePath -ErrorAction Stop
    $matchingLines = $logLines | Where-Object { $_ -like "*$expectedString*" }
    if ($matchingLines.Count -gt 0) {
        Write-Result -Msg "Log file contains expected string: '$expectedString'" -Success $true
        # Optionally, check timestamps for every 20 seconds during logout period
        # Since scenario only requires presence and timestamp, check timestamps
        $timestamps = @()
        foreach ($line in $matchingLines) {
            # Example log line format: [2024-06-01 12:34:56] Plugin run scheduler with CMDAgentCommunicationChannel:
            if ($line -match "^\[(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]") {
                $timestamps += $matches['ts']
            }
        }
        if ($timestamps.Count -gt 0) {
            Write-Result -Msg "Log file contains timestamps for expected entries" -Success $true
        } else {
            Write-Result -Msg "Log file does NOT contain timestamps for expected entries" -Success $false
        }
    } else {
        Write-Result -Msg "Log file does NOT contain expected string: '$expectedString'" -Success $false
    }
} catch {
    Write-Result -Msg "Failed to read log file: $_" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling $msiName silently..." -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn"
try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully (exit code: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstall failed (exit code: 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges for uninstall (exit code: 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstall returned unexpected exit code: $uninstallExitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

# Optionally verify service removal
Start-Sleep -Seconds 5
$serviceObj = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $serviceObj) {
    Write-Result -Msg "Service $serviceName removed after uninstall" -Success $true
} else {
    Write-Result -Msg "Service $serviceName still exists after uninstall" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "TEST RESULT: ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "TEST RESULT: SOME TESTS FAILED" -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')