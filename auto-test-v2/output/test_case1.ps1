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

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property' - $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Helper: Check if product is installed
function IsProductInstalled {
    param([string]$displayName)
    $products = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
    foreach ($prod in $products) {
        if ($prod.DisplayName -and ($prod.DisplayName.Trim() -eq $displayName.Trim())) {
            return $true
        }
    }
    return $false
}

# Pre-check: MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Pre-check: Product not already installed
if (IsProductInstalled $productName)) {
    Write-Result -Msg "$productName is already installed" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "$productName is not installed (OK to proceed)" -Success $true
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installLog = Join-Path $logDir "install_case1_$timestamp.log"
$msiExecArgs = "/i `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Installing MSI silently..." -ForegroundColor Cyan

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiExecArgs -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    Write-Host "msiexec exit code: $exitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "Exception during MSI installation - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

# Validate exit code
switch ($exitCode) {
    0     { Write-Result -Msg "MSI installed successfully (exit code 0)" -Success $true }
    3010  { Write-Result -Msg "MSI installed successfully (exit code 3010 - reboot required)" -Success $true }
    1603  { Write-Result -Msg "MSI installation failed (exit code 1603)" -Success $false; Stop-Transcript; exit 1 }
    1618  { Write-Result -Msg "Another installation in progress (exit code 1618)" -Success $false; Stop-Transcript; exit 1 }
    1925  { Write-Result -Msg "Insufficient privileges (exit code 1925)" -Success $false; Stop-Transcript; exit 1 }
    default { Write-Result -Msg "MSI installation returned unexpected exit code $exitCode" -Success $false; Stop-Transcript; exit 1 }
}

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verify product in installed programs
Write-Host "Verifying product in installed programs..." -ForegroundColor Cyan
$found = $false
$products = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
foreach ($prod in $products) {
    if ($prod.DisplayName -and ($prod.DisplayName.Trim() -eq $productName.Trim())) {
        $found = $true
        break
    }
}
Write-Result -Msg "$productName present in installed programs" -Success $found
if (-not $found) {
    Write-Host "[DEBUG] $productName not found in registry uninstall keys" -ForegroundColor Yellow
}

# 2. Verify service running
Write-Host "Verifying service $serviceName is running..." -ForegroundColor Cyan
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service $serviceName is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service $serviceName not found" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# 3. Verify service properties (StartMode, LogOnAs)
Write-Host "Verifying service properties..." -ForegroundColor Cyan
try {
    $svcWmi = Get-WmiObject Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $startMode = $svcWmi.StartMode
    $delayed = $svcWmi.DelayedAutoStart
    $logonAs = $svcWmi.StartName
    $expectedStartMode = "Auto"
    $expectedDelayed = $true
    $expectedLogon = "LocalSystem"
    $isStartMode = ($startMode -and ($startMode.Trim() -eq $expectedStartMode.Trim()))
    Write-Result -Msg "Service StartMode is $expectedStartMode" -Success $isStartMode
    if (-not $isStartMode) {
        Write-Host "[DEBUG] Expected StartMode: '$expectedStartMode', Actual: '$startMode'" -ForegroundColor Yellow
    }
    $isDelayed = ($delayed -eq $expectedDelayed)
    Write-Result -Msg "Service DelayedAutoStart is $expectedDelayed" -Success $isDelayed
    if (-not $isDelayed) {
        Write-Host "[DEBUG] Expected DelayedAutoStart: '$expectedDelayed', Actual: '$delayed'" -ForegroundColor Yellow
    }
    $isLogon = ($logonAs -and ($logonAs.Trim() -eq $expectedLogon.Trim()))
    Write-Result -Msg "Service Log On As is $expectedLogon" -Success $isLogon
    if (-not $isLogon) {
        Write-Host "[DEBUG] Expected LogOnAs: '$expectedLogon', Actual: '$logonAs'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to query service properties for $serviceName" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. Verify log file exists
Write-Host "Verifying log file $logFileName exists..." -ForegroundColor Cyan
$logPath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logPath
Write-Result -Msg "$logFileName exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file not found at $logPath" -ForegroundColor Yellow
}

# 5. Verify scheduled task exists
Write-Host "Verifying scheduled task exists..." -ForegroundColor Cyan
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction Stop
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $true
} catch {
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' not found" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# 6. Verify WMI namespace exists (no "Invalid namespace" error)
Write-Host "Verifying WMI namespace $wmiNamespace exists..." -ForegroundColor Cyan
try {
    $null = Get-WmiObject -Namespace $wmiNamespace -List -ErrorAction Stop
    Write-Result -Msg "WMI namespace $wmiNamespace is accessible" -Success $true
} catch {
    Write-Result -Msg "WMI namespace $wmiNamespace is NOT accessible" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling MSI silently..." -ForegroundColor Cyan
$uninstallArgs = "/x `"$msiPath`" /qn /l*v `"$installLog`""
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
    $uninstallExit = $uninstallProc.ExitCode
    Write-Host "msiexec uninstall exit code: $uninstallExit" -ForegroundColor Gray
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

switch ($uninstallExit) {
    0     { Write-Result -Msg "MSI uninstalled successfully (exit code 0)" -Success $true }
    3010  { Write-Result -Msg "MSI uninstalled successfully (exit code 3010 - reboot required)" -Success $true }
    1605  { Write-Result -Msg "Product not installed (exit code 1605)" -Success $true }
    1603  { Write-Result -Msg "MSI uninstall failed (exit code 1603)" -Success $false }
    1618  { Write-Result -Msg "Another installation in progress (exit code 1618)" -Success $false }
    1925  { Write-Result -Msg "Insufficient privileges (exit code 1925)" -Success $false }
    default { Write-Result -Msg "MSI uninstall returned unexpected exit code $uninstallExit" -Success $false }
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -cForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')