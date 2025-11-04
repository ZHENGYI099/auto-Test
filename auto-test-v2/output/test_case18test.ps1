# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case18test_$timestamp.log"

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
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$logDirPath = "C:\ProgramData\Microsoft\CMDExtension\Logs"
$pluginLogPath = Join-Path $logDirPath "PluginManagementPlugin.log"
$productCode = $null

# Check if product is already installed
try {
    $productCode = (Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Microsoft Cloud Managed Desktop Extension" }).IdentifyingNumber
} catch { $productCode = $null }

if ($productCode) {
    Write-Host "[FAIL] Product 'Microsoft Cloud Managed Desktop Extension' is already installed. Please uninstall before running this test." -ForegroundColor Red
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "Product not installed, ready for test." -Success $true
}

Write-Host ""

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing client agent..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=`"Test`" /qn"
$exitCode = $null

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $process.ExitCode
} catch {
    $exitCode = 9999
}

if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installation succeeded (exit code: $exitCode)" -Success $true
} else {
    Write-Result -Msg "MSI installation failed (exit code: $exitCode)" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 10
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq "Running") {
        Write-Result -Msg "Service '$serviceName' is running after install." -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' is NOT running after install." -Success $false
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found after install." -Success $false
}

Write-Host ""

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying plugin enable/disable logic..." -ForegroundColor Cyan

# Step 2: Wait 2 minutes, check logs for absence of two files
Write-Host "Waiting for 2 minutes for initial log generation..." -ForegroundColor Gray
Start-Sleep -Seconds 120

$commonPostLog = Join-Path $logDirPath "CommonPostProvisioningPlugin.log"
$pawnPluginLog = Join-Path $logDirPath "PawnPlugin.log"

$commonPostExists = Test-Path $commonPostLog
$pawnPluginExists = Test-Path $pawnPluginLog

Write-Result -Msg "'CommonPostProvisioningPlugin.log' does NOT exist (expected)" -Success (-not $commonPostExists)
Write-Result -Msg "'PawnPlugin.log' does NOT exist (expected)" -Success (-not $pawnPluginExists)

# Step 3: Send invalid plugin enable policy
$time = Get-Date
$versionstr = Get-Date -UFormat "%Y%m.%d%H.%M%S"
$payload = "{`"Type`":1,`"PluginId`":`"9c573ac5-3ad7-4680-81c1-3ec529ced175`",`"RequestTime`":`""+$time+"`",`"Payload`":`"True`"}"
$policy = @{
    PluginId="92611f58-44a1-4ff5-be2a-c27a53c15cd7"
    PluginName="PluginManagementPlugin"
    PolicyId="be8c130b-a7cb-42df-be90-344affa13e31"
    Version=$versionstr
    Status="Initial"
    Enabled="True"
    SchedulerMessage="SMSSchedule;ScheduleString=58419D0000080001"
    Payload=$payload
}

try {
    swmi -Namespace "root/cmd/clientagent" -Class "PluginPolicy" -Arguments $policy > $null
    Write-Result -Msg "Sent invalid plugin enable policy via WMI." -Success $true
} catch {
    Write-Result -Msg "Failed to send invalid plugin enable policy via WMI." -Success $false
}

# Step 4: Check PluginManagementPlugin.log for expected string
Start-Sleep -Seconds 10
$expectedStr1 = "9c573ac5-3ad7-4680-81c1-3ec529ced175 is not valid for the partner: "
$logContent = ""
if (Test-Path $pluginLogPath) {
    $logContent = Get-Content $pluginLogPath -Raw
    $found1 = $logContent -like "*$expectedStr1*"
    Write-Result -Msg "PluginManagementPlugin.log contains expected invalid plugin message." -Success $found1
} else {
    Write-Result -Msg "PluginManagementPlugin.log not found for invalid plugin check." -Success $false
}

# Step 5: Send valid plugin enable policy
$time = Get-Date
$versionstr = Get-Date -UFormat "%Y%m.%d%H.%M%S"
$payload = "{`"Type`":1,`"PluginId`":`"6251a87d-5ec4-4a5e-b836-f6c3a233b4e7`",`"RequestTime`":`""+$time+"`",`"Payload`":`"True`"}"
$policy = @{
    PluginId="92611f58-44a1-4ff5-be2a-c27a53c15cd7"
    PluginName="PluginManagementPlugin"
    PolicyId="be8c130b-a7cb-42df-be90-344affa13e31"
    Version=$versionstr
    Status="Initial"
    Enabled="True"
    SchedulerMessage="SMSSchedule;ScheduleString=58419D0000080001"
    Payload=$payload
}

try {
    swmi -Namespace "root/cmd/clientagent" -Class "PluginPolicy" -Arguments $policy > $null
    Write-Result -Msg "Sent valid plugin enable policy via WMI." -Success $true
} catch {
    Write-Result -Msg "Failed to send valid plugin enable policy via WMI." -Success $false
}

# Step 6: Check PluginManagementPlugin.log for expected success string
Start-Sleep -Seconds 10
$expectedStr2 = "update pluginid(6251a87d-5ec4-4a5e-b836-f6c3a233b4e7) enable state to enabled success"
$logContent = ""
if (Test-Path $pluginLogPath) {
    $logContent = Get-Content $pluginLogPath -Raw
    $found2 = $logContent -like "*$expectedStr2*"
    Write-Result -Msg "PluginManagementPlugin.log contains expected plugin enable success message." -Success $found2
} else {
    Write-Result -Msg "PluginManagementPlugin.log not found for plugin enable check." -Success $false
}

# Step 7: Send infra plugin disable policy
$time = Get-Date
$versionstr = Get-Date -UFormat "%Y%m.%d%H.%M%S"
$payload = "{`"Type`":1,`"PluginId`":`"caf0ee4a-1c93-4bdc-8644-746e94566750`",`"RequestTime`":`""+$time+"`",`"Payload`":`"False`"}"
$policy = @{
    PluginId="92611f58-44a1-4ff5-be2a-c27a53c15cd7"
    PluginName="PluginManagementPlugin"
    PolicyId="be8c130b-a7cb-42df-be90-344affa13e31"
    Version=$versionstr
    Status="Initial"
    Enabled="True"
    SchedulerMessage="SMSSchedule;ScheduleString=58419D0000080001"
    Payload=$payload
}

try {
    swmi -Namespace "root/cmd/clientagent" -Class "PluginPolicy" -Arguments $policy > $null
    Write-Result -Msg "Sent infra plugin disable policy via WMI." -Success $true
} catch {
    Write-Result -Msg "Failed to send infra plugin disable policy via WMI." -Success $false
}

# Step 7 Expected: Check PluginManagementPlugin.log for expected infra plugin string
Start-Sleep -Seconds 10
$expectedStr3 = "Infra plugin caf0ee4a-1c93-4bdc-8644-746e94566750 is not allowed to"
$logContent = ""
if (Test-Path $pluginLogPath) {
    $logContent = Get-Content $pluginLogPath -Raw
    $found3 = $logContent -like "*$expectedStr3*"
    Write-Result -Msg "PluginManagementPlugin.log contains expected infra plugin message." -Success $found3
} else {
    Write-Result -Msg "PluginManagementPlugin.log not found for infra plugin check." -Success $false
}

Write-Host ""

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling client agent..." -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn"
$uninstallExitCode = $null

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $uninstallExitCode = $process.ExitCode
} catch {
    $uninstallExitCode = 9999
}

if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 3010 -or $uninstallExitCode -eq 1605) {
    Write-Result -Msg "MSI uninstallation succeeded (exit code: $uninstallExitCode)" -Success $true
} else {
    Write-Result -Msg "MSI uninstallation failed (exit code: $uninstallExitCode)" -Success $false
}

# Verify service removed
Start-Sleep -Seconds 5
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Result -Msg "Service '$serviceName' still exists after uninstall (unexpected)." -Success $false
} catch {
    Write-Result -Msg "Service '$serviceName' removed after uninstall (expected)." -Success $true
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