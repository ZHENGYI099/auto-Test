# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case6test_$timestamp.log"

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
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"

# Check if MSI file exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed
$alreadyInstalled = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Microsoft Cloud Managed Desktop Extension" }
if ($alreadyInstalled) {
    Write-Result -Msg "Product already installed. Attempting uninstall before test..." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    if ($uninstallProcess.ExitCode -eq 0 -or $uninstallProcess.ExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed" -Success $true
    } else {
        Write-Result -Msg "Failed to remove previous installation (ExitCode: $($uninstallProcess.ExitCode))" -Success $false
        Stop-Transcript
        exit 1
    }
} else {
    Write-Result -Msg "Product not installed, ready for test" -Success $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI silently..." -ForegroundColor Cyan
$installArgs = "/i `"$msiPath`" SVCENV=Test /qn"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProcess.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installation succeeded (ExitCode: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (ExitCode: 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (ExitCode: 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (ExitCode: 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation failed (ExitCode: $exitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (max 5 min, check every 10 sec)
Write-Host "Waiting for service '$serviceName' to start..." -ForegroundColor Cyan
$serviceStarted = $false
for ($i=0; $i -lt 30; $i++) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $serviceStarted = $true
        break
    }
    Start-Sleep -Seconds 10
}
Write-Result -Msg "Service '$serviceName' running after install" -Success $serviceStarted

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================

# Wait up to 20 minutes for plugins to execute and logs to be generated
Write-Host "Waiting up to 20 minutes for plugin execution and log generation..." -ForegroundColor Cyan
$maxWaitSeconds = 1200
$waitInterval = 30
$elapsed = 0
while ($elapsed -lt $maxWaitSeconds) {
    $allLogsExist = (Test-Path "$logFolder\HeartbeatPlugin.log") -and
                    (Test-Path "$logFolder\GuardianTaskCheckerPlugin.log") -and
                    (Test-Path "$logFolder\MessageSenderPlugin.log")
    if ($allLogsExist) { break }
    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
}
Write-Result -Msg "All required log files exist in $logFolder" -Success $allLogsExist

# HeartbeatPlugin.log: "ServiceStatus: Running, Agent Version: [version-number], CpuUsage: [cpu-percentage], MemoryUsage: [memory-in-MB]"
$heartbeatLog = "$logFolder\HeartbeatPlugin.log"
$heartbeatPattern = "ServiceStatus: Running, Agent Version: .+, CpuUsage: .+, MemoryUsage: .+"
if (Test-Path $heartbeatLog) {
    $heartbeatContent = Get-Content $heartbeatLog -Raw
    $heartbeatMatch = $heartbeatContent -match $heartbeatPattern
    Write-Result -Msg "HeartbeatPlugin.log contains expected status line" -Success $heartbeatMatch
} else {
    Write-Result -Msg "HeartbeatPlugin.log not found" -Success $false
}

# GuardianTaskCheckerPlugin.log: "Check success for CMD Client Agent Guardian task (task folder name: CMD, task name: Cloud Managed Desktop Extension Health Evaluation)"
$guardianLog = "$logFolder\GuardianTaskCheckerPlugin.log"
$guardianPattern = "Check success for CMD Client Agent Guardian task \(task folder name: CMD, task name: Cloud Managed Desktop Extension Health Evaluation\)"
if (Test-Path $guardianLog) {
    $guardianContent = Get-Content $guardianLog -Raw
    $guardianMatch = $guardianContent -match $guardianPattern
    Write-Result -Msg "GuardianTaskCheckerPlugin.log contains expected check success line" -Success $guardianMatch
} else {
    Write-Result -Msg "GuardianTaskCheckerPlugin.log not found" -Success $false
}

# MessageSenderPlugin.log:
# 1. "Plugin 10a949a0-756f-46ab-aa74-68091f1612db executes policy b62873d6-2aec-403a-95ac-6e84250e46cd Success but failed to process the result to NoSender" - every 15 min
# 2. "Plugin 10a949a0-756f-46ab-aa74-68091f1612db executes policy f2fd6b33-6da7-4266-abbb-f74b129105d5 Success but failed to process the result to NoSender" - every 1 min
# 3. "Batch messages handler time watch : Updating message status duration" - at least once

$messageSenderLog = "$logFolder\MessageSenderPlugin.log"
$pattern1 = "Plugin 10a949a0-756f-46ab-aa74-68091f1612db executes policy b62873d6-2aec-403a-95ac-6e84250e46cd Success but failed to process the result to NoSender"
$pattern2 = "Plugin 10a949a0-756f-46ab-aa74-68091f1612db executes policy f2fd6b33-6da7-4266-abbb-f74b129105d5 Success but failed to process the result to NoSender"
$pattern3 = "Batch messages handler time watch : Updating message status duration"

if (Test-Path $messageSenderLog) {
    $msgContent = Get-Content $messageSenderLog -Raw
    $found1 = ($msgContent -match [regex]::Escape($pattern1))
    $found2 = ($msgContent -match [regex]::Escape($pattern2))
    $found3 = ($msgContent -match [regex]::Escape($pattern3))
    Write-Result -Msg "MessageSenderPlugin.log contains expected policy b62873d6 line" -Success $found1
    Write-Result -Msg "MessageSenderPlugin.log contains expected policy f2fd6b33 line" -Success $found2
    Write-Result -Msg "MessageSenderPlugin.log contains batch handler line" -Success $found3
} else {
    Write-Result -Msg "MessageSenderPlugin.log not found" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling MSI silently..." -ForegroundColor Cyan
$uninstallArgs = "/x `"$msiPath`" /qn"
try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstallation succeeded (ExitCode: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstallation failed (ExitCode: 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress during uninstall (ExitCode: 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges during uninstall (ExitCode: 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstallation failed (ExitCode: $uninstallExitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

# Verify service removed
$svcAfterUninstall = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
$serviceRemoved = -not $svcAfterUninstall
Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $serviceRemoved

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