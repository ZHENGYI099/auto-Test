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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property' - $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define MSI path and product name
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFileName = "CMDExtension.log"
$scheduledTaskName = "\Microsoft\CMD\Cloud Managed Desktop Extension Health Evaluation"
$wmiNamespace = "root\cmd\clientagent"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Write-Host "Cannot continue without MSI file." -ForegroundColor Red
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed
$alreadyInstalled = $false
try {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }
    if ($installed) {
        $alreadyInstalled = $true
        Write-Result -Msg "$productName is already installed" -Success $false
        Write-Host "Uninstalling existing product before test..." -ForegroundColor Yellow
        $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
        $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
        $exitCode = $uninstallProc.ExitCode
        if ($exitCode -eq 0 -or $exitCode -eq 1605) {
            Write-Result -Msg "Pre-test uninstall succeeded (exit code $exitCode)" -Success $true
        } else {
            Write-Result -Msg "Pre-test uninstall failed (exit code $exitCode)" -Success $false
            Write-Host "Cannot continue if uninstall fails." -ForegroundColor Red
            Stop-Transcript
            exit 1
        }
    } else {
        Write-Result -Msg "$productName is not installed (ready for test)" -Success $true
    }
} catch {
    Write-Result -Msg "Error checking installed products - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installLog = Join-Path $logDir "install_case1_$timestamp.log"
$msiArgs = "/i `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Installing $productName..." -ForegroundColor Cyan
try {
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    $exitCode = $proc.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 3010)
    Write-Result -Msg "MSI install exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] Install failed - see log: $installLog" -ForegroundColor Yellow
        Write-Host "Installation failed, skipping verification steps." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 5: Verify product is present in installed programs
try {
    $found = $false
    $products = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }
    if ($products) {
        $found = $true
    }
    Write-Result -Msg "$productName present in installed programs" -Success $found
    if (-not $found) {
        Write-Host "[DEBUG] Product not found in Win32_Product" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Error checking installed programs - $($_.Exception.Message)" -Success $false
}

# Step 6: Verify service is running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service $serviceName is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service $serviceName not found - $($_.Exception.Message)" -Success $false
}

# Step 7: Verify service details (Status, StartupType, LogOnAs)
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop

    $statusOk = $false
    if ($null -ne $svcWmi.State -and -not [string]::IsNullOrWhiteSpace($svcWmi.State)) {
        $statusOk = ($svcWmi.State.Trim() -eq "Running")
    }
    $startupOk = $false
    if ($null -ne $svcWmi.StartMode -and -not [string]::IsNullOrWhiteSpace($svcWmi.StartMode)) {
        $startupOk = ($svcWmi.StartMode.Trim() -eq "Auto")
    }
    $delayedOk = $false
    if ($svcWmi.DelayedAutoStart -ne $null) {
        $delayedOk = $svcWmi.DelayedAutoStart
    }
    $startupTypeOk = ($startupOk -and $delayedOk)
    $logonOk = $false
    if ($null -ne $svcWmi.StartName -and -not [string]::IsNullOrWhiteSpace($svcWmi.StartName)) {
        $logonOk = ($svcWmi.StartName.Trim() -eq "LocalSystem")
    }

    Write-Result -Msg "Service $serviceName status is Running" -Success $statusOk
    if (-not $statusOk) {
        Write-Host "[DEBUG] Service State: $($svcWmi.State)" -ForegroundColor Yellow
    }
    Write-Result -Msg "Service $serviceName startup type is Automatic (Delayed Start)" -Success $startupTypeOk
    if (-not $startupTypeOk) {
        Write-Host "[DEBUG] StartMode: $($svcWmi.StartMode), DelayedAutoStart: $($svcWmi.DelayedAutoStart)" -ForegroundColor Yellow
    }
    Write-Result -Msg "Service $serviceName Log On As Local System" -Success $logonOk
    if (-not $logonOk) {
        Write-Host "[DEBUG] StartName: $($svcWmi.StartName)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Error checking service details - $($_.Exception.Message)" -Success $false
}

# Step 8: Verify log file exists
$logFilePath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logFilePath
Write-Result -Msg "$logFileName exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file missing: $logFilePath" -ForegroundColor Yellow
}

# Step 9: Verify scheduled task exists
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction Stop
    $taskExists = $true
} catch {
    $taskExists = $false
}
Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $taskExists
if (-not $taskExists) {
    Write-Host "[DEBUG] Scheduled task not found: $scheduledTaskName" -ForegroundColor Yellow
}

# Step 10: Verify WMI namespace is valid (no Invalid namespace error)
try {
    $wmiTest = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
    $wmiNamespaceValid = $true
} catch {
    $wmiNamespaceValid = $false
}
Write-Result -Msg "WMI namespace $wmiNamespace is valid (no Invalid namespace error)" -Success $wmiNamespaceValid
if (-not $wmiNamespaceValid) {
    Write-Host "[DEBUG] WMI namespace invalid: $wmiNamespace" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling $productName..." -ForegroundColor Cyan
try {
    $uninstallArgs = "/x `"$msiPath`" /qn /l*v `"$logDir\uninstall_case1_$timestamp.log`""
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $uninstallExit = $uninstallProc.ExitCode
    $uninstallSuccess = ($uninstallExit -eq 0 -or $uninstallExit -eq 1605)
    Write-Result -Msg "MSI uninstall exit code $uninstallExit" -Success $uninstallSuccess
    if (-not $uninstallSuccess) {
        Write-Host "[DEBUG] Uninstall failed - see log: $logDir\uninstall_case1_$timestamp.log" -ForegroundColor Yellow
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