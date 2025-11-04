# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$testCaseId = "case25test"
$logFile = Join-Path $logDir "test_${testCaseId}_$timestamp.log"

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
    Write-Host "❌ ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define MSI path and service name
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$agentExePath = "C:\Program Files\Microsoft Cloud Managed Desktop Extension\CMDExtension.exe"
$logFolder = "C:\ProgramData\Microsoft\CloudManagementDesktop\Extension\Logs"
$logFileName = "CMDExtension.log"
$cmdLogPath = Join-Path $logFolder $logFileName

# Helper: Get MSI property (per instructions)
function Get-MSIProperty {
    param(
        [string]$msiPath,
        [string]$property
    )
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $installer, @($msiPath, 0))
        $query = "SELECT Value FROM Property WHERE Property = '$property'"
        $view = $database.GetType().InvokeMember("OpenView", 'InvokeMethod', $null, $database, ($query))
        $null = $view.GetType().InvokeMember("Execute", 'InvokeMethod', $null, $view, $null)
        $record = $view.GetType().InvokeMember("Fetch", 'InvokeMethod', $null, $view, $null)
        $value = $null
        if ($record -ne $null) {
            $value = $record.GetType().InvokeMember("StringData", 'GetProperty', $null, $record, 1)
        }
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }
        return $value.Trim()
    } catch {
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property': $_" -ForegroundColor Yellow
        return $null
    }
}

# Check if agent is already installed (by service)
$serviceInstalled = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceInstalled) {
    Write-Host "Agent service '$serviceName' already installed. Uninstalling before test..." -ForegroundColor Yellow
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    Write-Result -Msg "Pre-test uninstall exit code: $exitCode" -Success (($exitCode -eq 0) -or ($exitCode -eq 1605))
    Start-Sleep -Seconds 5
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing CMD Agent..." -ForegroundColor Cyan

# Install agent with SVCENV=Test (per scenario)
$installArgs = "/i `"$msiPath`" /qn SVCENV=Test"
$installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
$installExitCode = $installProc.ExitCode
Write-Result -Msg "Agent install exit code: $installExitCode" -Success (($installExitCode -eq 0) -or ($installExitCode -eq 3010))

# Wait for service to start (max 60s, poll every 5s)
$maxWait = 60
$pollInterval = 5
$serviceStarted = $false
for ($i=0; $i -lt ($maxWait/$pollInterval); $i++) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        $serviceStarted = $true
        break
    }
    Start-Sleep -Seconds $pollInterval
}
Write-Result -Msg "Agent service '$serviceName' running after install" -Success $serviceStarted

# Wait 60s for agent to initialize (per scenario)
Start-Sleep -Seconds 60

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying registry and agent status..." -ForegroundColor Cyan

# Step 1: Registry checks
try {
    $settingsRegPath = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"
    $settings = Get-ItemProperty -Path $settingsRegPath -ErrorAction Stop
    $partners = $settings.Partners
    if ([string]::IsNullOrWhiteSpace($partners)) {
        Write-Result -Msg "Registry Partners is null or empty" -Success $false
    } else {
        $partners = $partners.Trim()
        Write-Result -Msg "Registry Partners = CPC" -Success ($partners -eq "CPC")
        if ($partners -ne "CPC") {
            Write-Host "[DEBUG] Expected: 'CPC', Actual: '$partners'" -ForegroundColor Yellow
        }
    }
    $partnersTagDict = $settings.PartnersTagDict
    if ([string]::IsNullOrWhiteSpace($partnersTagDict)) {
        Write-Result -Msg "Registry PartnersTagDict is null or empty" -Success $false
    } else {
        $partnersTagDict = $partnersTagDict.Trim()
        Write-Result -Msg "Registry PartnersTagDict = CPC=TEST01" -Success ($partnersTagDict -eq "CPC=TEST01")
        if ($partnersTagDict -ne "CPC=TEST01") {
            Write-Host "[DEBUG] Expected: 'CPC=TEST01', Actual: '$partnersTagDict'" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Result -Msg "Registry Settings key missing or unreadable" -Success $false
}

try {
    $diagRegPath = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\DiagnosticInfo"
    $diag = Get-ItemProperty -Path $diagRegPath -ErrorAction Stop
    $registerStatus = $diag.DeviceClientRegisterStatus
    if ([string]::IsNullOrWhiteSpace($registerStatus)) {
        Write-Result -Msg "DeviceClientRegisterStatus is null or empty" -Success $false
    } else {
        $registerStatus = $registerStatus.Trim()
        Write-Result -Msg "DeviceClientRegisterStatus = Registered" -Success ($registerStatus -eq "Registered")
        if ($registerStatus -ne "Registered") {
            Write-Host "[DEBUG] Expected: 'Registered', Actual: '$registerStatus'" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Result -Msg "Registry DiagnosticInfo key missing or unreadable" -Success $false
}

# Step 2: Enable "Block iot" firewall rule
Write-Host "Enabling 'Block iot' firewall rule..." -ForegroundColor Cyan
$fwRuleName = "Block iot"
try {
    $rule = Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction Stop
    Enable-NetFirewallRule -DisplayName $fwRuleName
    Write-Result -Msg "'Block iot' firewall rule enabled" -Success $true
} catch {
    Write-Result -Msg "'Block iot' firewall rule not found" -Success $false
}

# Wait 15 minutes for agent to react
Start-Sleep -Seconds 900

# Step 3: Log file checks for disconnect/retry
Write-Host "Checking agent log for disconnect/retry events..." -ForegroundColor Cyan
$logContent = ""
if (Test-Path $cmdLogPath) {
    $logContent = Get-Content -Path $cmdLogPath -Raw
    $logContent = $logContent.Trim()
    $disconnectRetry = $logContent -match "Connection status changed: status=Disconnected_Retrying, reason=Communication_Error"
    $disconnectExpired = $logContent -match "Connection status changed: status=Disconnected, reason=Retry_Expired"
    $startReregister = $logContent -match "Start to re-register"
    $alreadyRegistering = $logContent -match "DeviceManager already started registering."
    $disposeBeforeCreate = $logContent -match "Dispose device client before create new one"

    Write-Result -Msg "Log contains 'Disconnected_Retrying, Communication_Error'" -Success $disconnectRetry
    Write-Result -Msg "Log contains 'Disconnected, Retry_Expired'" -Success $disconnectExpired
    Write-Result -Msg "Log contains 'Start to re-register'" -Success $startReregister
    Write-Result -Msg "Log contains 'DeviceManager already started registering.'" -Success $alreadyRegistering
    Write-Result -Msg "Log contains 'Dispose device client before create new one'" -Success $disposeBeforeCreate
} else {
    Write-Result -Msg "CMDExtension.log file not found" -Success $false
}

# Step 4: Disable "Block iot" firewall rule
Write-Host "Disabling 'Block iot' firewall rule..." -ForegroundColor Cyan
try {
    Disable-NetFirewallRule -DisplayName $fwRuleName
    Write-Result -Msg "'Block iot' firewall rule disabled" -Success $true
} catch {
    Write-Result -Msg "Failed to disable 'Block iot' firewall rule" -Success $false
}

# Wait 2 minutes for agent to reconnect
Start-Sleep -Seconds 120

# Step 4: Log file checks for reconnect
if (Test-Path $cmdLogPath) {
    $logContent = Get-Content -Path $cmdLogPath -Raw
    $logContent = $logContent.Trim()
    $connectedOk = $logContent -match "Connection status changed: status=Connected, reason=Connection_Ok"
    $clientOpened = $logContent -match "DeviceClient created and opened successfully"
    Write-Result -Msg "Log contains 'Connected, Connection_Ok'" -Success $connectedOk
    Write-Result -Msg "Log contains 'DeviceClient created and opened successfully'" -Success $clientOpened
} else {
    Write-Result -Msg "CMDExtension.log file not found (after reconnect)" -Success $false
}

# Step 5: Enable "Block iot" firewall again
Write-Host "Enabling 'Block iot' firewall rule again..." -ForegroundColor Cyan
try {
    Enable-NetFirewallRule -DisplayName $fwRuleName
    Write-Result -Msg "'Block iot' firewall rule re-enabled" -Success $true
} catch {
    Write-Result -Msg "Failed to re-enable 'Block iot' firewall rule" -Success $false
}

# Wait 10 minutes (less than 15 as per scenario)
Start-Sleep -Seconds 600

# Step 5: Disable "Block iot" firewall rule
Write-Host "Disabling 'Block iot' firewall rule after second disconnect..." -ForegroundColor Cyan
try {
    Disable-NetFirewallRule -DisplayName $fwRuleName
    Write-Result -Msg "'Block iot' firewall rule disabled (final)" -Success $true
} catch {
    Write-Result -Msg "Failed to disable 'Block iot' firewall rule (final)" -Success $false
}

# Step 6: Log file checks for disconnect/reconnect sequence, and absence of re-register
if (Test-Path $cmdLogPath) {
    $logContent = Get-Content -Path $cmdLogPath -Raw
    $logContent = $logContent.Trim()
    $disconnectRetry2 = $logContent -match "Connection status changed: status=Disconnected_Retrying, reason=Communication_Error"
    $connectedOk2 = $logContent -match "Connection status changed: status=Connected, reason=Connection_Ok"
    $startReregister2 = $logContent -match "Start to re-register"
    Write-Result -Msg "Log contains 'Disconnected_Retrying, Communication_Error' (after step5)" -Success $disconnectRetry2
    Write-Result -Msg "Log contains 'Connected, Connection_Ok' (after step5)" -Success $connectedOk2
    Write-Result -Msg "Log does NOT contain 'Start to re-register' during time1/time2" -Success (-not $startReregister2)
} else {
    Write-Result -Msg "CMDExtension.log file not found (final check)" -Success $false
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling CMD Agent..." -ForegroundColor Cyan
$uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
$uninstallExitCode = $uninstallProc.ExitCode
Write-Result -Msg "Agent uninstall exit code: $uninstallExitCode" -Success (($uninstallExitCode -eq 0) -or ($uninstallExitCode -eq 1605))

# Verify service removed
$svcAfterUninstall = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
Write-Result -Msg "Agent service '$serviceName' removed after uninstall" -Success (-not $svcAfterUninstall)

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