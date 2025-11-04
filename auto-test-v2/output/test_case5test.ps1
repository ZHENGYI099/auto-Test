# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$test_case_id = "case5test"
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
} else {
    Write-Result -Msg "Running as Administrator" -Success $true
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$pluginLogDir = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$mainLogFile = Join-Path $pluginLogDir "CMDExtension.log"
$heartbeatPluginLog = Join-Path $pluginLogDir "HeartbeatPlugin.log"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed
$installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Microsoft Cloud Managed Desktop Extension" }
if ($installed) {
    Write-Result -Msg "Product already installed. Attempting silent uninstall before test." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed successfully (exit code $uninstallExitCode)" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (exit code $uninstallExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} else {
    Write-Result -Msg "Product not installed. Ready for test." -Success $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI silently with SVCENV=PreProduction..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=PreProduction /qn"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProcess.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (exit code $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (exit code 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (exit code 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation failed (exit code $exitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait 3 minutes for agent registration attempts
Write-Host "Waiting 3 minutes for agent registration attempts..." -ForegroundColor Yellow
Start-Sleep -Seconds 180

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================

# 1. Verify failure logs and retry attempts in CMDExtension.log
$logFound = $false
$retryFound = $false
$invalidHttpFound = $false

if (Test-Path $mainLogFile) {
    $logContent = Get-Content $mainLogFile -Raw
    if ($logContent -match "InvalidHttpResponse. StatusCode: 401") {
        $invalidHttpFound = $true
        Write-Result -Msg "CMDExtension.log contains 'InvalidHttpResponse. StatusCode: 401'" -Success $true
    } else {
        Write-Result -Msg "CMDExtension.log does NOT contain 'InvalidHttpResponse. StatusCode: 401'" -Success $false
    }
    if ($logContent -match "retry" -or $logContent -match "Retry") {
        $retryFound = $true
        Write-Result -Msg "CMDExtension.log contains retry attempts" -Success $true
    } else {
        Write-Result -Msg "CMDExtension.log does NOT contain retry attempts" -Success $false
    }
} else {
    Write-Result -Msg "CMDExtension.log not found at $mainLogFile" -Success $false
}

# 2. Verify there is NO plugin log (HeartbeatPlugin.log)
if (-not (Test-Path $heartbeatPluginLog)) {
    Write-Result -Msg "HeartbeatPlugin.log does NOT exist (expected)" -Success $true
} else {
    Write-Result -Msg "HeartbeatPlugin.log exists (unexpected)" -Success $false
}

# 3. Verify WMI namespace root\cmd\clientagent: SchedulerEntity instances is empty
try {
    $wmiInstances = Get-WmiObject -Namespace "root\cmd\clientagent" -Class "SchedulerEntity" -ErrorAction Stop
    if ($wmiInstances.Count -eq 0) {
        Write-Result -Msg "WMI SchedulerEntity instance list is empty (expected)" -Success $true
    } else {
        Write-Result -Msg "WMI SchedulerEntity instance list is NOT empty (unexpected)" -Success $false
    }
} catch {
    # If namespace/class does not exist, treat as empty (since agent registration failed)
    Write-Result -Msg "WMI SchedulerEntity class not found (treated as empty, expected)" -Success $true
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
        Write-Result -Msg "MSI uninstalled successfully (exit code $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstall failed (exit code 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress during uninstall (exit code 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges during uninstall (exit code 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstall failed (exit code $uninstallExitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $($script:SuccessCount)" -ForegroundColor Green
Write-Host "Total Failed: $($script:FailCount)" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "TEST RESULT: [PASS] All checks passed." -ForegroundColor Green
} else {
    Write-Host "TEST RESULT: [FAIL] Some checks failed." -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')