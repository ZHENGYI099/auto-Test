# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case7test_$timestamp.log"

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
$productName = "Microsoft Cloud Managed Desktop Extension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$clientHealthLog = Join-Path $logFolder "ClientHealth.log"

# Check if product already installed
function Get-InstalledProduct {
    param([string]$msiName)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        Get-ChildItem $regPath | ForEach-Object {
            $displayName = $_.GetValue("DisplayName")
            if ($displayName -and $displayName -like "*$productName*") {
                return $true
            }
        }
    }
    return $false
}

if (Get-InstalledProduct -msiName $productName) {
    Write-Result -Msg "Product '$productName' is already installed. Uninstall before running this test." -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "Product '$productName' is not installed." -Success $true
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing '$productName' from $msiPath ..." -ForegroundColor Cyan

$installCmd = "msiexec.exe /i `"$msiPath`" /qn"
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
$exitCode = $installProcess.ExitCode

if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installation succeeded (ExitCode: $exitCode)" -Success $true
} else {
    Write-Result -Msg "MSI installation failed (ExitCode: $exitCode)" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to appear and start
$maxWait = 30
$waited = 0
while ($waited -lt $maxWait) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
}
if ($null -eq $svc) {
    Write-Result -Msg "Service '$serviceName' not found after installation." -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "Service '$serviceName' found after installation." -Success $true
}

# Ensure service is running
if ($svc.Status -eq 'Running') {
    Write-Result -Msg "Service '$serviceName' is running after installation." -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' is NOT running after installation." -Success $false
}

Write-Host ""
# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Starting verification phase..." -ForegroundColor Cyan

# --- Step 5: Run scheduled task and verify result ---
Write-Host "Running scheduled task: Cloud Managed Desktop Extension Health Evaluation..." -ForegroundColor Cyan
$taskPath = "\Microsoft\CMD\Cloud Managed Desktop Extension Health Evaluation"
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction Stop
    Start-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    Start-Sleep -Seconds 5
    $taskInfo = Get-ScheduledTaskInfo -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Result -Msg "Scheduled task completed successfully (LastTaskResult: 0)" -Success $true
    } else {
        Write-Result -Msg "Scheduled task failed (LastTaskResult: $($taskInfo.LastTaskResult))" -Success $false
    }
} catch {
    Write-Result -Msg "Scheduled task not found or could not be run." -Success $false
}

# --- Step 6: Verify ClientHealth.log for specific JSON report ---
Write-Host "Verifying ClientHealth.log for expected health report..." -ForegroundColor Cyan
$expectedJson = '[{"ID":"a2f3177d-1f1d-4580-8b30-1eb4e8c0da69","RuleEvaluationResult":"Pass","ResultDetails":null},{"ID":"489f82c9-5b8f-4a71-aa51-109a1919b76b","RuleEvaluationResult":"Pass","ResultDetails":null},{"ID":"88d25de5-34da-4d58-9240-1d8e914ec641","RuleEvaluationResult":"Pass","ResultDetails":null},{"ID":"ad14a7c7-fd00-4820-a99f-fa561ff96c8f","RuleEvaluationResult":"Fail","ResultDetails":"Registry not found, it may be happened on agent installing/upgrading."}]'

if (Test-Path $clientHealthLog) {
    $logContent = Get-Content $clientHealthLog -Raw
    if ($logContent -match [regex]::Escape($expectedJson)) {
        Write-Result -Msg "ClientHealth.log contains expected health report JSON." -Success $true
    } else {
        Write-Result -Msg "ClientHealth.log does NOT contain expected health report JSON." -Success $false
    }
} else {
    Write-Result -Msg "ClientHealth.log not found at $clientHealthLog." -Success $false
}

# --- Step 7: Stop service, rerun guardian task, verify log ---
Write-Host "Stopping service '$serviceName'..." -ForegroundColor Cyan
try {
    Stop-Service -Name $serviceName -Force
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name $serviceName
    if ($svc.Status -eq 'Stopped') {
        Write-Result -Msg "Service '$serviceName' stopped successfully." -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' did not stop as expected." -Success $false
    }
} catch {
    Write-Result -Msg "Failed to stop service '$serviceName'." -Success $false
}

# Rerun scheduled task
try {
    Start-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    Start-Sleep -Seconds 5
    $taskInfo = Get-ScheduledTaskInfo -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    Write-Result -Msg "Scheduled task re-run after service stop (LastTaskResult: $($taskInfo.LastTaskResult))" -Success ($taskInfo.LastTaskResult -eq 0)
} catch {
    Write-Result -Msg "Scheduled task could not be re-run after service stop." -Success $false
}

# Verify log for expected remediation messages
$expectedMsgs = @(
    "Service is not running, current status is Stopped",
    "After trying remediation, current status is Running",
    "Summary: rule Verify/Remediate CMD Client Agent service running status. with ID 489f82c9-5b8f-4a71-aa51-109a1919b76b, result = PassAfterRemediation"
)
if (Test-Path $clientHealthLog) {
    $logContent = Get-Content $clientHealthLog -Raw
    $allFound = $true
    foreach ($msg in $expectedMsgs) {
        if ($logContent -match [regex]::Escape($msg)) {
            Write-Result -Msg "ClientHealth.log contains: '$msg'" -Success $true
        } else {
            Write-Result -Msg "ClientHealth.log missing: '$msg'" -Success $false
            $allFound = $false
        }
    }
} else {
    Write-Result -Msg "ClientHealth.log not found for remediation check." -Success $false
}

# --- Step 9: Set service startup type to Disabled, rerun guardian task, verify log ---
Write-Host "Setting service '$serviceName' startup type to Disabled..." -ForegroundColor Cyan
try {
    Set-Service -Name $serviceName -StartupType Disabled
    Start-Sleep -Seconds 2
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
    if ($svcWmi.StartMode -eq "Disabled") {
        Write-Result -Msg "Service startup type set to Disabled." -Success $true
    } else {
        Write-Result -Msg "Service startup type NOT set to Disabled." -Success $false
    }
} catch {
    Write-Result -Msg "Failed to set service startup type to Disabled." -Success $false
}

# Rerun scheduled task
try {
    Start-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    Start-Sleep -Seconds 5
    $taskInfo = Get-ScheduledTaskInfo -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation"
    Write-Result -Msg "Scheduled task re-run after startup type change (LastTaskResult: $($taskInfo.LastTaskResult))" -Success ($taskInfo.LastTaskResult -eq 0)
} catch {
    Write-Result -Msg "Scheduled task could not be re-run after startup type change." -Success $false
}

# Verify log for expected startup type remediation messages
$expectedMsgs2 = @(
    "Service startup type is not automatic, current startup type is Disabled",
    "Set service startMode to delayed automatic.",
    "Summary: rule Verify/Remediate CMD Client Agent Service startup type. with ID 88d25de5-34da-4d58-9240-1d8e914ec641, result = PassAfterRemediation"
)
if (Test-Path $clientHealthLog) {
    $logContent = Get-Content $clientHealthLog -Raw
    $allFound2 = $true
    foreach ($msg in $expectedMsgs2) {
        if ($logContent -match [regex]::Escape($msg)) {
            Write-Result -Msg "ClientHealth.log contains: '$msg'" -Success $true
        } else {
            Write-Result -Msg "ClientHealth.log missing: '$msg'" -Success $false
            $allFound2 = $false
        }
    }
} else {
    Write-Result -Msg "ClientHealth.log not found for startup type remediation check." -Success $false
}

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Starting cleanup phase: Uninstalling product..." -ForegroundColor Cyan

$uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
$uninstallExitCode = $uninstallProcess.ExitCode

if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 3010) {
    Write-Result -Msg "MSI uninstallation succeeded (ExitCode: $uninstallExitCode)" -Success $true
} elseif ($uninstallExitCode -eq 1605) {
    Write-Result -Msg "MSI uninstallation: product not installed (ExitCode: $uninstallExitCode)" -Success $true
} else {
    Write-Result -Msg "MSI uninstallation failed (ExitCode: $uninstallExitCode)" -Success $false
}

# Verify service is removed
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall." -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still present after uninstall." -Success $false
}

Write-Host ""
# ============================================================
# SUMMARY
# ============================================================
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