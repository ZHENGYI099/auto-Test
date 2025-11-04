# ============================================================
# SETUP LOGGING
# ============================================================
$test_case_id = "case17test"
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
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$logFilePath = "C:\ProgramData\Microsoft\CloudManagedDesktopExtension\CMDExtension.log"

# Check if product is already installed
$installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "Microsoft Cloud Managed Desktop Extension" }
if ($installed) {
    Write-Result -Msg "Product already installed: Microsoft Cloud Managed Desktop Extension" -Success $true
} else {
    Write-Result -Msg "Product not installed: Microsoft Cloud Managed Desktop Extension" -Success $true
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing agent..." -ForegroundColor Cyan

$installNeeded = $false
if (-not $installed) {
    $installNeeded = $true
}

if ($installNeeded) {
    $installCmd = "msiexec.exe /i `"$msiPath`" SVCENV=Test /qn"
    Write-Host "Executing: $installCmd" -ForegroundColor Gray
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$msiPath`"", "SVCENV=Test", "/qn" -Wait -PassThru
    $exitCode = $process.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installation succeeded (ExitCode: $exitCode)" -Success $true
    } else {
        Write-Result -Msg "MSI installation failed (ExitCode: $exitCode)" -Success $false
        Stop-Transcript
        exit 2
    }
} else {
    Write-Host "Installation not needed, product already present." -ForegroundColor Gray
}

# Wait for service to be present
$maxWait = 60
$waited = 0
while ($waited -lt $maxWait) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) { break }
    Start-Sleep -Seconds 2
    $waited += 2
}
if ($svc) {
    Write-Result -Msg "Service $serviceName found after installation" -Success $true
} else {
    Write-Result -Msg "Service $serviceName NOT found after installation" -Success $false
    Stop-Transcript
    exit 3
}

Write-Host ""
# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Executing test scenario steps..." -ForegroundColor Cyan

# --- Step 2: Create Outbound Rule "Block amqp" (TCP 5671) ---
$fwRuleNameAmqp = "Block amqp"
$fwRuleExistsAmqp = Get-NetFirewallRule -DisplayName $fwRuleNameAmqp -ErrorAction SilentlyContinue
if (-not $fwRuleExistsAmqp) {
    try {
        New-NetFirewallRule -DisplayName $fwRuleNameAmqp -Direction Outbound -Action Block -Protocol TCP -LocalPort 5671 -Profile Any | Out-Null
        Write-Result -Msg "Created firewall rule: $fwRuleNameAmqp" -Success $true
    } catch {
        Write-Result -Msg "Failed to create firewall rule: $fwRuleNameAmqp" -Success $false
    }
} else {
    Write-Host "Firewall rule $fwRuleNameAmqp already exists, enabling it." -ForegroundColor Gray
    Set-NetFirewallRule -DisplayName $fwRuleNameAmqp -Enabled True
    Write-Result -Msg "Enabled firewall rule: $fwRuleNameAmqp" -Success $true
}

# --- Step 3: Restart Service ---
try {
    Restart-Service -Name $serviceName -Force -ErrorAction Stop
    Write-Result -Msg "Service $serviceName restarted" -Success $true
} catch {
    Write-Result -Msg "Failed to restart service $serviceName" -Success $false
}

# --- Step 4: Check log for "DeviceClient created and opened successfully" ---
$logFound1 = $false
if (Test-Path $logFilePath) {
    $logFound1 = Select-String -Path $logFilePath -Pattern "DeviceClient created and opened successfully" -SimpleMatch -Quiet
}
Write-Result -Msg "Log contains 'DeviceClient created and opened successfully' after amqp block" -Success $logFound1

# --- Step 5: Stop Service ---
try {
    Stop-Service -Name $serviceName -Force -ErrorAction Stop
    Write-Result -Msg "Service $serviceName stopped" -Success $true
} catch {
    Write-Result -Msg "Failed to stop service $serviceName" -Success $false
}

# --- Step 6: Create Outbound Rule "Block https" (TCP 443) ---
$fwRuleNameHttps = "Block https"
$fwRuleExistsHttps = Get-NetFirewallRule -DisplayName $fwRuleNameHttps -ErrorAction SilentlyContinue
if (-not $fwRuleExistsHttps) {
    try {
        New-NetFirewallRule -DisplayName $fwRuleNameHttps -Direction Outbound -Action Block -Protocol TCP -LocalPort 443 -Profile Any | Out-Null
        Write-Result -Msg "Created firewall rule: $fwRuleNameHttps" -Success $true
    } catch {
        Write-Result -Msg "Failed to create firewall rule: $fwRuleNameHttps" -Success $false
    }
} else {
    Write-Host "Firewall rule $fwRuleNameHttps already exists, enabling it." -ForegroundColor Gray
    Set-NetFirewallRule -DisplayName $fwRuleNameHttps -Enabled True
    Write-Result -Msg "Enabled firewall rule: $fwRuleNameHttps" -Success $true
}

# --- Step 7: Start Service and wait 35 minutes ---
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Result -Msg "Service $serviceName started" -Success $true
} catch {
    Write-Result -Msg "Failed to start service $serviceName" -Success $false
}
Write-Host "Waiting 35 minutes for agent behavior..." -ForegroundColor Yellow
Start-Sleep -Seconds 2100

# --- Step 8: Check log for "Connect to IoTHub failed with a generic exception" ---
$logFound2 = $false
if (Test-Path $logFilePath) {
    $logFound2 = Select-String -Path $logFilePath -Pattern "Connect to IoTHub failed with a generic exception" -SimpleMatch -Quiet
}
Write-Result -Msg "Log contains 'Connect to IoTHub failed with a generic exception' after https block" -Success $logFound2

# --- Step 9: Disable "Block https" rule and wait 10 minutes ---
try {
    Set-NetFirewallRule -DisplayName $fwRuleNameHttps -Enabled False
    Write-Result -Msg "Disabled firewall rule: $fwRuleNameHttps" -Success $true
} catch {
    Write-Result -Msg "Failed to disable firewall rule: $fwRuleNameHttps" -Success $false
}
Write-Host "Waiting 10 minutes for agent recovery..." -ForegroundColor Yellow
Start-Sleep -Seconds 600

# --- Step 10: Check log for "DeviceClient created and opened successfully" ---
$logFound3 = $false
if (Test-Path $logFilePath) {
    $logFound3 = Select-String -Path $logFilePath -Pattern "DeviceClient created and opened successfully" -SimpleMatch -Quiet
}
Write-Result -Msg "Log contains 'DeviceClient created and opened successfully' after https unblock" -Success $logFound3

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up test artifacts..." -ForegroundColor Cyan

# Remove or disable firewall rules
foreach ($ruleName in @($fwRuleNameAmqp, $fwRuleNameHttps)) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        try {
            Remove-NetFirewallRule -DisplayName $ruleName
            Write-Result -Msg "Removed firewall rule: $ruleName" -Success $true
        } catch {
            Write-Result -Msg "Failed to remove firewall rule: $ruleName" -Success $false
        }
    } else {
        Write-Result -Msg "Firewall rule not found for cleanup: $ruleName" -Success $true
    }
}

# Uninstall agent
Write-Host "Uninstalling agent..." -ForegroundColor Gray
$uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x", "`"$msiPath`"", "/qn" -Wait -PassThru
$exitCode = $process.ExitCode
if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1605) {
    Write-Result -Msg "MSI uninstall succeeded (ExitCode: $exitCode)" -Success $true
} else {
    Write-Result -Msg "MSI uninstall failed (ExitCode: $exitCode)" -Success $false
}

# Verify service removed
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Result -Msg "Service $serviceName removed after uninstall" -Success $true
} else {
    Write-Result -Msg "Service $serviceName still present after uninstall" -Success $false
}

Write-Host ""
# ============================================================
# SUMMARY
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST EXECUTION COMPLETE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "Test Case ID: $test_case_id" -ForegroundColor Gray
Write-Host "Successes: $script:SuccessCount" -ForegroundColor Green
Write-Host "Failures:  $script:FailCount" -ForegroundColor Red
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')