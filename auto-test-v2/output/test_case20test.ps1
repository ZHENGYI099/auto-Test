# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case20test_$timestamp.log"

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
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$expectedNamespace = "root/cmd/clientagent"
$expectedClass = "HighPriorityIoTHubMessage"
$logFolder = "C:\ProgramData\CloudManagedDesktop\Logs"
$pluginLog = Join-Path $logFolder "MessageSenderPlugin.log"

# Helper function for MSI property reading (per instructions)
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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property': $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Check if product is already installed (by service existence)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service $serviceName already installed. Attempting uninstall before test." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    Write-Host "Uninstalling existing product..." -ForegroundColor Yellow
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed successfully." -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation. Exit code $exitCode" -Success $false
        Stop-Transcript
        exit 2
    }
    Start-Sleep -Seconds 5
}

Write-Host "Pre-checks complete." -ForegroundColor Cyan
Write-Host ""

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Starting installation..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=`"Test`" /qn"
try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully. Exit code $exitCode" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "Installation failed - Fatal error (1603)." -Success $false
        Stop-Transcript
        exit 3
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (1618)." -Success $false
        Stop-Transcript
        exit 4
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (1925)." -Success $false
        Stop-Transcript
        exit 5
    } else {
        Write-Result -Msg "Installation failed - Unexpected exit code $exitCode" -Success $false
        Stop-Transcript
        exit 6
    }
} catch {
    Write-Result -Msg "Exception during installation: $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 7
}

# Wait for service to start
$maxWait = 30
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
Write-Result -Msg "Service $serviceName running after install" -Success $serviceStarted

Write-Host ""

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Starting verification..." -ForegroundColor Cyan

# Step 2: Send 20 HighPriorityIoTHubMessage instances via swmi (Set-WmiInstance)
$payload = "abcdefghijklmn"
for ($i=1; $i -le 10; $i++) { $payload += $payload }

$sendSuccess = $true
for ($i=1; $i -le 20; $i++) {
    try {
        $null = Set-WmiInstance -Namespace $expectedNamespace -Class $expectedClass -Arguments @{
            PluginId="7d3e8eff-7a14-4d03-8861-efde7514feac"
            PolicyId="00000000-0000-0000-0000-000000000000"
            Status="Active"
            CreatedAt="20221118063702.429394+000"
            MessageId=([guid]::NewGuid().ToString())
            CorrelationId=([guid]::NewGuid().ToString())
            Payload=$payload
        }
    } catch {
        Write-Host "[DEBUG] Failed to send message at iteration $i - $($_.Exception.Message)" -ForegroundColor Yellow
        $sendSuccess = $false
    }
}
Write-Result -Msg "Sent 20 HighPriorityIoTHubMessage instances via swmi" -Success $sendSuccess

# Step 2 Verification: Check WMI for 20 instances
try {
    $instances = Get-WmiObject -Namespace $expectedNamespace -Class $expectedClass
    $count = ($instances | Measure-Object).Count
    $isCount20 = ($count -eq 20)
    Write-Result -Msg "WMI contains 20 HighPriorityIoTHubMessage instances" -Success $isCount20
    if (-not $isCount20) {
        Write-Host "[DEBUG] Actual instance count: $count" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to enumerate WMI instances: $($_.Exception.Message)" -Success $false
}

# Step 3: Wait for 1 minute before log verification
Write-Host "Waiting 1 minute for logs to be generated..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Step 3 Verification: Check MessageSenderPlugin.log for expected log entries
$expectedLogEntries = @(
    "Plugin 10a949a0-756f-46ab-aa74-68091f1612db executes policy f2fd6b33-6da7-4266-abbb-f74b129105d5 Success but failed to process the result to NoSender",
    "Start to send 14 messages(size: 200704B) to IotHub",
    "Start to send 6 messages(size: 86016B) to IotHub"
)

if (Test-Path $pluginLog) {
    $logContent = Get-Content -Path $pluginLog -Raw
    $allFound = $true
    foreach ($entry in $expectedLogEntries) {
        $found = $false
        if (-not [string]::IsNullOrWhiteSpace($logContent)) {
            $logContentTrimmed = $logContent.Trim()
            $found = ($logContentTrimmed -like "*$entry*")
        }
        Write-Result -Msg "Log contains expected entry: $entry" -Success $found
        if (-not $found) {
            $allFound = $false
            Write-Host "[DEBUG] Missing log entry: $entry" -ForegroundColor Yellow
        }
    }
} else {
    Write-Result -Msg "MessageSenderPlugin.log not found at $pluginLog" -Success $false
    $allFound = $false
}

Write-Host ""

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Starting cleanup..." -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn"
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully. Exit code $exitCode" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "Uninstall failed - Fatal error (1603)." -Success $false
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (1618)." -Success $false
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (1925)." -Success $false
    } else {
        Write-Result -Msg "Uninstall failed - Unexpected exit code $exitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during uninstall: $($_.Exception.Message)" -Success $false
}

# Verify service removal
Start-Sleep -Seconds 5
$svcAfterUninstall = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
Write-Result -Msg "Service $serviceName removed after uninstall" -Success (-not $svcAfterUninstall)

Write-Host ""

# ============================================================
# TEST EXECUTION SUMMARY
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