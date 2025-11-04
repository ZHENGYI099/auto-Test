# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case16test_$timestamp.log"

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

# Helper function for result tracking
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
}

# Define MSI path and service name
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$productName = "Microsoft Cloud Managed Desktop Extension"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed (service exists)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service '$serviceName' already installed. Attempting uninstall for clean state..." -Success $false
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
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing '$productName'..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=`"Test`" /qn"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $installExitCode = $installProcess.ExitCode
    Write-Host "MSI install exit code: $installExitCode" -ForegroundColor Gray
    if ($installExitCode -eq 0 -or $installExitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (exit code: $installExitCode)" -Success $true
    } elseif ($installExitCode -eq 1603) {
        Write-Result -Msg "Installation failed (exit code: 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($installExitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($installExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "Unknown MSI install exit code: $installExitCode" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI install: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to appear and start
$maxWait = 60
$waited = 0
$serviceStarted = $false
while ($waited -lt $maxWait) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $serviceStarted = $true
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
}
Write-Result -Msg "Service '$serviceName' running after install" -Success $serviceStarted

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Testing guardian restart behavior..." -ForegroundColor Cyan

# Step: Stop the service
try {
    Stop-Service -Name $serviceName -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Stopped') {
        Write-Result -Msg "Service '$serviceName' stopped successfully" -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' did not stop as expected" -Success $false
    }
} catch {
    Write-Result -Msg "Exception stopping service: $_" -Success $false
}

# Step: Wait for guardian to restart the agent
# NOTE: Human step says "Wait for more than 24 hours OR speed up by steps show in Discussion"
# For automation, we will poll for up to 5 minutes for the service to restart
$maxRestartWait = 300 # seconds
$restartWaited = 0
$serviceRestarted = $false
while ($restartWaited -lt $maxRestartWait) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Running') {
        $serviceRestarted = $true
        break
    }
    Start-Sleep -Seconds 5
    $restartWaited += 5
}
Write-Result -Msg "Guardian restarted service '$serviceName' within $maxRestartWait seconds" -Success $serviceRestarted

# Final verification: Service should be running
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Result -Msg "Final check: Service '$serviceName' is running" -Success $true
} else {
    Write-Result -Msg "Final check: Service '$serviceName' is NOT running" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling '$productName'..." -ForegroundColor Cyan

try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    Write-Host "MSI uninstall exit code: $uninstallExitCode" -ForegroundColor Gray
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully (exit code: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "Uninstall failed (exit code: 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
    } else {
        Write-Result -Msg "Unknown MSI uninstall exit code: $uninstallExitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

Start-Sleep -Seconds 5

# Verify service is removed
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still exists after uninstall" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "TEST RESULT: SUCCESS" -ForegroundColor Green
} else {
    Write-Host "TEST RESULT: FAILED" -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')