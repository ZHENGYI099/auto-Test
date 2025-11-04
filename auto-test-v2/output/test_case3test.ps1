# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case3test_$timestamp.log"

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
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logFolder "CMDExtension.log"

# Check MSI file exists
if (Test-Path $msiPath) {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
} else {
    Write-Result -Msg "MSI file NOT found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
}

# Check if product already installed (by service existence)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service '$serviceName' already exists. Attempting uninstall before install." -Success $false
    # Attempt uninstall
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed (exit code: $uninstallExitCode)" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (exit code: $uninstallExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
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
Write-Host "Installing MSI silently..." -ForegroundColor Cyan
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    $installExitCode = $installProcess.ExitCode
    Write-Host "MSI install exit code: $installExitCode" -ForegroundColor Gray
    if ($installExitCode -eq 0 -or $installExitCode -eq 3010) {
        Write-Result -Msg "MSI installation succeeded (exit code: $installExitCode)" -Success $true
    } elseif ($installExitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed - Fatal error (exit code: $installExitCode)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($installExitCode -eq 1618) {
        Write-Result -Msg "MSI installation failed - Another installation in progress (exit code: $installExitCode)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($installExitCode -eq 1925) {
        Write-Result -Msg "MSI installation failed - Insufficient privileges (exit code: $installExitCode)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation failed (exit code: $installExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to appear and start (max 90 seconds)
$maxWaitSeconds = 90
$waited = 0
$serviceStarted = $false
while ($waited -lt $maxWaitSeconds) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $serviceStarted = $true
        break
    }
    Start-Sleep -Seconds 3
    $waited += 3
}
Write-Host "Waited $waited seconds for service '$serviceName' to start." -ForegroundColor Gray

if ($serviceStarted) {
    Write-Result -Msg "Service '$serviceName' is running after installation" -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' did NOT start after installation" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================

# 1. Service running?
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Result -Msg "Service '$serviceName' exists" -Success $true
    Write-Result -Msg "Service '$serviceName' status: $($svc.Status)" -Success ($svc.Status -eq 'Running')
} catch {
    Write-Result -Msg "Service '$serviceName' not found" -Success $false
}

# 2. Service properties (DisplayName, StartupType, LogOnAs)
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    Write-Result -Msg "Service DisplayName: $($svcWmi.DisplayName)" -Success ($svcWmi.DisplayName -eq $productName)
    Write-Result -Msg "Service StartupType: $($svcWmi.StartMode)" -Success ($svcWmi.StartMode -eq "Auto")
    Write-Result -Msg "Service LogOnAs: $($svcWmi.StartName)" -Success ($svcWmi.StartName -eq "LocalSystem")
} catch {
    Write-Result -Msg "Service WMI object not found" -Success $false
}

# 3. Log file existence
if (Test-Path $logFilePath) {
    Write-Result -Msg "Log file exists: $logFilePath" -Success $true
} else {
    Write-Result -Msg "Log file NOT found: $logFilePath" -Success $false
}

# 4. Log file content: at least 2 lines of "Start up args length: 0"
$startupArgsCount = 0
if (Test-Path $logFilePath) {
    try {
        $lines = Get-Content $logFilePath -ErrorAction Stop
        $startupArgsCount = ($lines | Select-String -Pattern "Start up args length: 0").Count
        Write-Result -Msg "Log file contains $startupArgsCount lines with 'Start up args length: 0'" -Success ($startupArgsCount -ge 2)
    } catch {
        Write-Result -Msg "Failed to read log file: $_" -Success $false
    }
} else {
    Write-Result -Msg "Cannot check log file content; file missing" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling MSI silently..." -ForegroundColor Cyan
try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    Write-Host "MSI uninstall exit code: $uninstallExitCode" -ForegroundColor Gray
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstallation succeeded (exit code: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstallation failed - Fatal error (exit code: $uninstallExitCode)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "MSI uninstallation failed - Another installation in progress (exit code: $uninstallExitCode)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "MSI uninstallation failed - Insufficient privileges (exit code: $uninstallExitCode)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstallation failed (exit code: $uninstallExitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstallation: $_" -Success $false
}

# Verify service removed
$svcRemoved = $false
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $svcRemoved = $false
} catch {
    $svcRemoved = $true
}
Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $svcRemoved

# Verify log file removed
$logFileGone = -not (Test-Path $logFilePath)
Write-Result -Msg "Log file removed after uninstall" -Success $logFileGone

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "OVERALL RESULT: [PASS] All checks succeeded." -ForegroundColor Green
} else {
    Write-Host "OVERALL RESULT: [FAIL] Some checks failed. See log for details." -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')