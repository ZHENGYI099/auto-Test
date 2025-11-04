# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case1test_$timestamp.log"

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
    Write-Host "❌ ERROR - Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define constants
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFileName = "CMDExtension.log"
$scheduledTaskPath = "\Microsoft\CMD\Cloud Managed Desktop Extension Health Evaluation"
$wmiNamespace = "root\cmd\clientagent"

# Helper: Get MSI property (do NOT modify this function)
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

# Helper: Check if product is installed
function Is-ProductInstalled {
    param([string]$displayName)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -and ($props.DisplayName.Trim() -eq $displayName)) {
                return $true
            }
        }
    }
    return $false
}

# Pre-check: MSI file exists
if (-not (Test-Path $msiPath)) {
    Write-Host "❌ ERROR - MSI file not found at $msiPath" -ForegroundColor Red
    Stop-Transcript
    exit 2
}
Write-Result -Msg "MSI file found at $msiPath" -Success $true

# Pre-check: Product not already installed
if (Is-ProductInstalled -displayName $productName) {
    Write-Host "❌ ERROR - Product '$productName' is already installed. Uninstall before running this test." -ForegroundColor Red
    Stop-Transcript
    exit 3
}
Write-Result -Msg "Product '$productName' not installed (ready for test)" -Success $true

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installLog = Join-Path $logDir "install_case1test_$timestamp.log"
$msiExecCmd = "msiexec.exe /i `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Installing MSI silently..." -ForegroundColor Cyan

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn /l*v `"$installLog`"" -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    Write-Host "MSIExec exit code: $exitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "MSI installation process failed to start" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 4
}

# Exit code handling
$successCodes = @(0, 3010)
if ($successCodes -contains $exitCode) {
    Write-Result -Msg "MSI installation succeeded (exit code $exitCode)" -Success $true
} elseif ($exitCode -eq 1603) {
    Write-Result -Msg "MSI installation failed (exit code 1603 - installation failure)" -Success $false
    Stop-Transcript
    exit 1603
} elseif ($exitCode -eq 1618) {
    Write-Result -Msg "MSI installation failed (exit code 1618 - another installation in progress)" -Success $false
    Stop-Transcript
    exit 1618
} elseif ($exitCode -eq 1925) {
    Write-Result -Msg "MSI installation failed (exit code 1925 - insufficient privileges)" -Success $false
    Stop-Transcript
    exit 1925
} else {
    Write-Result -Msg "MSI installation failed (exit code $exitCode)" -Success $false
    Stop-Transcript
    exit $exitCode
}

# Wait for service to appear (max 30s)
$maxWait = 30
$waited = 0
while ($waited -lt $maxWait) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) { break }
    Start-Sleep -Seconds 2
    $waited += 2
}
if ($svc) {
    Write-Result -Msg "Service '$serviceName' detected after install" -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' NOT detected after install" -Success $false
}

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verify product in installed programs (registry)
$foundProduct = $false
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
foreach ($regPath in $regPaths) {
    $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($props.DisplayName -and ($props.DisplayName.Trim() -eq $productName)) {
            $foundProduct = $true
            break
        }
    }
    if ($foundProduct) { break }
}
Write-Result -Msg "Installed programs contains '$productName'" -Success $foundProduct
if (-not $foundProduct) {
    Write-Host "[DEBUG] '$productName' not found in registry uninstall keys" -ForegroundColor Yellow
}

# 2. Verify service running
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service '$serviceName' is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} else {
    Write-Result -Msg "Service '$serviceName' not found" -Success $false
}

# 3. Verify service properties (WMI)
$svcWmi = Get-WmiObject Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($svcWmi) {
    # Status
    $status = $svcWmi.State
    $isRunning = ($status.Trim() -eq "Running")
    Write-Result -Msg "Service '$serviceName' WMI State is 'Running'" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Expected: 'Running', Actual: '$status'" -ForegroundColor Yellow
    }
    # Startup Type
    $startMode = $svcWmi.StartMode
    $expectedStartMode = "Delayed Auto"
    $isStartMode = ($startMode.Trim() -eq $expectedStartMode)
    Write-Result -Msg "Service '$serviceName' Startup Type is '$expectedStartMode'" -Success $isStartMode
    if (-not $isStartMode) {
        Write-Host "[DEBUG] Expected: '$expectedStartMode', Actual: '$startMode'" -ForegroundColor Yellow
    }
    # Log On As
    $logon = $svcWmi.StartName
    $expectedLogon = "LocalSystem"
    $isLogon = ($logon.Trim() -eq $expectedLogon)
    Write-Result -Msg "Service '$serviceName' Log On As is '$expectedLogon'" -Success $isLogon
    if (-not $isLogon) {
        Write-Host "[DEBUG] Expected: '$expectedLogon', Actual: '$logon'" -ForegroundColor Yellow
    }
} else {
    Write-Result -Msg "Service '$serviceName' not found in WMI" -Success $false
}

# 4. Verify log file exists
$logFilePath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logFilePath
Write-Result -Msg "Log file '$logFileName' exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file path: $logFilePath" -ForegroundColor Yellow
}

# 5. Verify scheduled task exists
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction SilentlyContinue
    $taskExists = ($task -ne $null)
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $taskExists
    if (-not $taskExists) {
        Write-Host "[DEBUG] Scheduled task not found at $scheduledTaskPath" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Scheduled task query failed" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# 6. Verify WMI namespace exists (no "Invalid namespace" error)
try {
    $wmiObj = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
    Write-Result -Msg "WMI namespace '$wmiNamespace' is accessible (no error)" -Success $true
} catch {
    Write-Result -Msg "WMI namespace '$wmiNamespace' is NOT accessible (Invalid namespace)" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling product..." -ForegroundColor Cyan
try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn /l*v `"$installLog`"" -Wait -PassThru -WindowStyle Hidden
    $uninstallExit = $uninstallProcess.ExitCode
    Write-Host "MSIExec uninstall exit code: $uninstallExit" -ForegroundColor Gray
} catch {
    Write-Result -Msg "MSI uninstall process failed to start" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 5
}

# Uninstall exit code handling
if ($successCodes -contains $uninstallExit) {
    Write-Result -Msg "MSI uninstall succeeded (exit code $uninstallExit)" -Success $true
} elseif ($uninstallExit -eq 1605) {
    Write-Result -Msg "MSI uninstall failed (exit code 1605 - product not installed)" -Success $false
} else {
    Write-Result -Msg "MSI uninstall failed (exit code $uninstallExit)" -Success $false
}

# Verify service removed
$svcAfter = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
$svcRemoved = ($svcAfter -eq $null)
Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $svcRemoved
if (-not $svcRemoved) {
    Write-Host "[DEBUG] Service still present after uninstall" -ForegroundColor Yellow
}

# Verify product removed from installed programs
$productRemoved = -not (Is-ProductInstalled -displayName $productName)
Write-Result -Msg "Product '$productName' removed from installed programs" -Success $productRemoved
if (-not $productRemoved) {
    Write-Host "[DEBUG] Product still present in registry uninstall keys after uninstall" -ForegroundColor Yellow
}

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