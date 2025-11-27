# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case24test_$timestamp.log"

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
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
    exit 1
}

# Define paths and names
$msiPath = "C:\VMShare\cmdextension.msi"
$toastScript = "C:\VMShare\test_toast.ps1"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$userNotificationsLog = Join-Path $logFolder "UserNotificationsPlugin.log"

# Check MSI presence
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Write-Host "Aborting test due to missing MSI." -ForegroundColor Red
    Stop-Transcript
    exit 2
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check toast script presence
if (-not (Test-Path $toastScript)) {
    Write-Result -Msg "Toast script not found at $toastScript" -Success $false
    Write-Host "Aborting test due to missing toast script." -ForegroundColor Red
    Stop-Transcript
    exit 3
} else {
    Write-Result -Msg "Toast script found at $toastScript" -Success $true
}

# Check if product already installed (service exists and running)
$svc = $null
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq "Running") {
        Write-Result -Msg "Service $serviceName already running - uninstalling before test" -Success $false
        Write-Host "Attempting to uninstall existing product..." -ForegroundColor Yellow
        $uninstallArgs = "/x `"$msiPath`" /qn"
        $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
        $exitCode = $uninstallProc.ExitCode
        if ($exitCode -eq 0 -or $exitCode -eq 1605 -or $exitCode -eq 3010) {
            Write-Result -Msg "Previous installation removed (exit code $exitCode)" -Success $true
        } else {
            Write-Result -Msg "Failed to uninstall previous installation (exit code $exitCode)" -Success $false
            Write-Host "Aborting test due to uninstall failure." -ForegroundColor Red
            Stop-Transcript
            exit 4
        }
        Start-Sleep -Seconds 10
    }
} catch {
    Write-Result -Msg "No existing service $serviceName found" -Success $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI..." -ForegroundColor Cyan
$installArgs = "/i `"$msiPath`" SVCENV=Test /qn"
try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProc.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 3010)
    Write-Result -Msg "MSI installation exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] MSI install failed - exit code $exitCode" -ForegroundColor Yellow
        Write-Host "Aborting test due to installation failure." -ForegroundColor Red
        Stop-Transcript
        exit 5
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Write-Host "Aborting test due to install exception." -ForegroundColor Red
    Stop-Transcript
    exit 6
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 10
$svc = $null
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq "Running") {
        Write-Result -Msg "Service $serviceName is running after install" -Success $true
    } else {
        Write-Result -Msg "Service $serviceName not running after install (Status: $($svc.Status))" -Success $false
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service $serviceName not found after install" -Success $false
    Write-Host "[DEBUG] Exception: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================

# Step 5: Wait 10 minutes
Write-Host "Waiting 10 minutes for agent initialization..." -ForegroundColor Cyan
Start-Sleep -Seconds 600

# Step 5: Run toast script (handle execution policy if needed)
Write-Host "Running toast notification script..." -ForegroundColor Cyan
$toastSuccess = $false
try {
    & $toastScript
    $toastSuccess = $true
    Write-Result -Msg "Toast script executed successfully" -Success $true
} catch {
    Write-Host "Execution policy may be blocking script - setting to Bypass and retrying..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        & $toastScript
        $toastSuccess = $true
        Write-Result -Msg "Toast script executed successfully after policy bypass" -Success $true
    } catch {
        Write-Result -Msg "Failed to execute toast script - $($_.Exception.Message)" -Success $false
    }
}

# Step 6: UX popup verification - NO script check (visual only, skip)

# Step 7: Check UserNotificationsPlugin.log for required contents
Write-Host "Checking UserNotificationsPlugin.log for expected contents..." -ForegroundColor Cyan
$logExists = Test-Path $userNotificationsLog
Write-Result -Msg "UserNotificationsPlugin.log exists" -Success $logExists
if ($logExists) {
    $logContent = Get-Content $userNotificationsLog -Raw
    $checks = @(
        @{ Text = 'The UX input is : {"TemplateType":"sampleTemplate"'; Desc = 'UX input line present' },
        @{ Text = 'DisplayUserNotification is waiting for the UX to be closed'; Desc = 'DisplayUserNotification waiting line present' }
    )
    foreach ($check in $checks) {
        if ([string]::IsNullOrWhiteSpace($logContent)) {
            Write-Result -Msg "$($check.Desc) - log content is empty" -Success $false
        } else {
            $found = $logContent.Trim() -like "*$($check.Text)*"
            Write-Result -Msg "$($check.Desc)" -Success $found
            if (-not $found) {
                Write-Host "[DEBUG] Expected text not found: '$($check.Text)'" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "[DEBUG] Log file missing: $userNotificationsLog" -ForegroundColor Yellow
}

# Step 8: "Delay 4 Hours" - UI only, no script action

# Step 9: Check UserNotificationsPlugin.log again (no explicit expect result, but action is to open log)
# Since no new expect result, just confirm file still exists
Write-Host "Re-checking UserNotificationsPlugin.log exists after delay..." -ForegroundColor Cyan
$logExists2 = Test-Path $userNotificationsLog
Write-Result -Msg "UserNotificationsPlugin.log exists after delay" -Success $logExists2

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling MSI for cleanup..." -ForegroundColor Cyan
$uninstallArgs = "/x `"$msiPath`" /qn"
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 1605 -or $exitCode -eq 3010)
    Write-Result -Msg "MSI uninstall exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] MSI uninstall failed - exit code $exitCode" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')