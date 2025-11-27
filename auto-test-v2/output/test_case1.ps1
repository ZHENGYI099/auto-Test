# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case1_$timestamp.log"

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

# Helper: Get MSI property (do not modify this function)
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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property' - $_" -ForegroundColor Yellow
        return $null
    }
}

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define paths and names
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFileName = "CMDExtension.log"
$scheduledTaskPath = "\Microsoft\CMD\Cloud Managed Desktop Extension Health Evaluation"
$wmiNamespace = "root\cmd\clientagent"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 2
}

# Check if product already installed (by DisplayName in registry)
$installed = $false
try {
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem -Path $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $displayName = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            if ($displayName) {
                if ($displayName.Trim() -eq $productName.Trim()) {
                    $installed = $true
                    break
                }
            }
        }
        if ($installed) { break }
    }
} catch {
    Write-Host "[DEBUG] Exception checking installed products - $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($installed) {
    Write-Result -Msg "$productName is already installed - uninstall before test" -Success $false
    Stop-Transcript
    exit 3
} else {
    Write-Result -Msg "$productName is not installed - ready for installation" -Success $true
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Install MSI silently (/qn)
Write-Host "Installing $productName from $msiPath ..." -ForegroundColor Cyan
$installLog = Join-Path $logDir "install_case1_$timestamp.log"
$msiExecArgs = "/i `"$msiPath`" /qn /l*v `"$installLog`""
$exitCode = $null

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiExecArgs -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    Write-Host "msiexec exit code: $exitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "Exception during MSI installation - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 4
}

# Validate exit code
if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installation succeeded (exit code $exitCode)" -Success $true
} elseif ($exitCode -eq 1603) {
    Write-Result -Msg "MSI installation failed (exit code 1603)" -Success $false
    Write-Host "[DEBUG] See install log at $installLog" -ForegroundColor Yellow
    Stop-Transcript
    exit 5
} elseif ($exitCode -eq 1618) {
    Write-Result -Msg "Another installation in progress (exit code 1618)" -Success $false
    Stop-Transcript
    exit 6
} elseif ($exitCode -eq 1925) {
    Write-Result -Msg "Insufficient privileges (exit code 1925)" -Success $false
    Stop-Transcript
    exit 7
} else {
    Write-Result -Msg "MSI installation failed (exit code $exitCode)" -Success $false
    Write-Host "[DEBUG] See install log at $installLog" -ForegroundColor Yellow
    Stop-Transcript
    exit 8
}

# Wait for service to start (max 30s)
$serviceStarted = $false
for ($i = 0; $i -lt 6; $i++) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and ($svc.Status -eq "Running")) {
        $serviceStarted = $true
        break
    }
    Start-Sleep -Seconds 5
}
if ($serviceStarted) {
    Write-Result -Msg "$serviceName service started" -Success $true
} else {
    Write-Result -Msg "$serviceName service did not start within 30s" -Success $false
}

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 5: Verify product in installed programs
Write-Host "Verifying product in installed programs..." -ForegroundColor Cyan
$foundProduct = $false
try {
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem -Path $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $displayName = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            if ($displayName) {
                if ($displayName.Trim() -eq $productName.Trim()) {
                    $foundProduct = $true
                    break
                }
            }
        }
        if ($foundProduct) { break }
    }
} catch {
    Write-Host "[DEBUG] Exception checking installed programs - $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Result -Msg "$productName present in installed programs" -Success $foundProduct
if (-not $foundProduct) {
    Write-Host "[DEBUG] Expected: '$productName', Actual: Not found" -ForegroundColor Yellow
}

# Step 6: Verify service running
Write-Host "Verifying service status..." -ForegroundColor Cyan
try {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and ($svc.Status -eq "Running")) {
        Write-Result -Msg "$serviceName is running" -Success $true
    } else {
        Write-Result -Msg "$serviceName is not running" -Success $false
        if ($svc) {
            Write-Host "[DEBUG] Actual status: $($svc.Status)" -ForegroundColor Yellow
        } else {
            Write-Host "[DEBUG] Service not found" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Result -Msg "Exception checking $serviceName status" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 7: Verify service properties (Status, StartupType, LogOnAs)
Write-Host "Verifying service properties..." -ForegroundColor Cyan
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
    if ($svcWmi) {
        $statusMatch = ($svcWmi.State -and ($svcWmi.State.Trim() -eq "Running"))
        $startupMatch = ($svcWmi.StartMode -and ($svcWmi.StartMode.Trim() -eq "Delayed Auto Start" -or $svcWmi.StartMode.Trim() -eq "Auto"))
        $logonMatch = ($svcWmi.StartName -and ($svcWmi.StartName.Trim() -eq "LocalSystem"))
        Write-Result -Msg "$serviceName - Status is Running" -Success $statusMatch
        if (-not $statusMatch) {
            Write-Host "[DEBUG] Expected: 'Running', Actual: '$($svcWmi.State)'" -ForegroundColor Yellow
        }
        Write-Result -Msg "$serviceName - Startup Type is Automatic (Delayed Start)" -Success $startupMatch
        if (-not $startupMatch) {
            Write-Host "[DEBUG] Expected: 'Delayed Auto Start' or 'Auto', Actual: '$($svcWmi.StartMode)'" -ForegroundColor Yellow
        }
        Write-Result -Msg "$serviceName - Log On As is Local System" -Success $logonMatch
        if (-not $logonMatch) {
            Write-Host "[DEBUG] Expected: 'LocalSystem', Actual: '$($svcWmi.StartName)'" -ForegroundColor Yellow
        }
    } else {
        Write-Result -Msg "$serviceName not found in Win32_Service" -Success $false
    }
} catch {
    Write-Result -Msg "Exception checking $serviceName properties" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 8: Verify log file exists
Write-Host "Verifying log file presence..." -ForegroundColor Cyan
$logPath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logPath
Write-Result -Msg "$logFileName exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Expected: '$logPath', Actual: Not found" -ForegroundColor Yellow
}

# Step 9: Verify scheduled task exists
Write-Host "Verifying scheduled task presence..." -ForegroundColor Cyan
$taskExists = $false
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction SilentlyContinue
    if ($task) {
        $taskExists = $true
    }
} catch {
    $taskExists = $false
}
Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $taskExists
if (-not $taskExists) {
    Write-Host "[DEBUG] Expected: '$scheduledTaskPath', Actual: Not found" -ForegroundColor Yellow
}

# Step 10: Verify WMI namespace does NOT show "Invalid namespace"
Write-Host "Verifying WMI namespace..." -ForegroundColor Cyan
$wmiNamespaceValid = $true
try {
    $null = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
    $wmiNamespaceValid = $true
} catch {
    if ($_.Exception.Message -match "Invalid namespace") {
        $wmiNamespaceValid = $false
    }
}
Write-Result -Msg "WMI namespace '$wmiNamespace' is valid (no 'Invalid namespace' error)" -Success $wmiNamespaceValid
if (-not $wmiNamespaceValid) {
    Write-Host "[DEBUG] WMI namespace '$wmiNamespace' returned 'Invalid namespace'" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling $productName ..." -ForegroundColor Cyan
$uninstallArgs = "/x `"$msiPath`" /qn /l*v `"$installLog`""
$uninstallExitCode = $null
try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
    $uninstallExitCode = $process.ExitCode
    Write-Host "msiexec uninstall exit code: $uninstallExitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 9
}

if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 3010) {
    Write-Result -Msg "MSI uninstall succeeded (exit code $uninstallExitCode)" -Success $true
} elseif ($uninstallExitCode -eq 1605) {
    Write-Result -Msg "Product not installed (exit code 1605)" -Success $true
} else {
    Write-Result -Msg "MSI uninstall failed (exit code $uninstallExitCode)" -Success $false
    Write-Host "[DEBUG] See uninstall log at $installLog" -ForegroundColor Yellow
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