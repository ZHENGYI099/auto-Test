# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_test1case_$timestamp.log"

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

# Define constants
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$expectedLogFile = "CMDExtension.log"
$scheduledTaskPath = "\Microsoft\CMD\Cloud Managed Desktop Extension Health Evaluation"
$wmiNamespace = "root\cmd\clientagent"

# Helper: Get MSI property (per spec)
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
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $found = $false
    try {
        $keys = Get-ChildItem -Path $uninstallKey
        foreach ($key in $keys) {
            $props = Get-ItemProperty -Path $key.PSPath
            if ($props.DisplayName -and ($props.DisplayName.Trim() -eq $displayName)) {
                $found = $true
                break
            }
        }
    } catch {
        Write-Host "[DEBUG] Failed to query uninstall registry - $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return $found
}

Write-Host "Checking if $productName is already installed..." -ForegroundColor Cyan
$alreadyInstalled = Is-ProductInstalled -displayName $productName
Write-Result -Msg "$productName already installed check" -Success (-not $alreadyInstalled)
if ($alreadyInstalled) {
    Write-Host "ERROR - $productName is already installed. Uninstall before running this test." -ForegroundColor Red
    Stop-Transcript
    exit 2
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installLog = Join-Path $logDir "install_cmdextension_$timestamp.log"
$msiexecArgs = "/i `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Installing $productName silently..." -ForegroundColor Cyan

$exitCode = $null
try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiexecArgs -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
} catch {
    Write-Host "[FAIL] msiexec failed to start - $($_.Exception.Message)" -ForegroundColor Red
    $script:FailCount++
    $exitCode = $null
}

if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installation succeeded (exit code $exitCode)" -Success $true
} else {
    Write-Result -Msg "MSI installation failed (exit code $exitCode)" -Success $false
    Write-Host "[DEBUG] See install log: $installLog" -ForegroundColor Yellow
    Stop-Transcript
    exit 3
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
Write-Result -Msg "Service $serviceName appeared after install" -Success ($svc -ne $null)

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verify product in installed programs
Write-Host "Verifying product in installed programs..." -ForegroundColor Cyan
$foundProduct = Is-ProductInstalled -displayName $productName
Write-Result -Msg "$productName present in installed programs" -Success $foundProduct
if (-not $foundProduct) {
    Write-Host "[DEBUG] $productName not found in uninstall registry" -ForegroundColor Yellow
}

# 2. Verify service running
Write-Host "Verifying service $serviceName running..." -ForegroundColor Cyan
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service $serviceName is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} else {
    Write-Result -Msg "Service $serviceName not found" -Success $false
}

# 3. Verify service properties (StartMode, LogOnAs)
Write-Host "Verifying service properties..." -ForegroundColor Cyan
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    # StartMode: "Automatic (Delayed Start)" maps to StartMode="Auto" and DelayedAutoStart=$true
    $startMode = $svcWmi.StartMode
    $delayed = $svcWmi.DelayedAutoStart
    $logonAs = $svcWmi.StartName
    $isAutoDelayed = ($startMode.Trim() -eq "Auto" -and $delayed -eq $true)
    Write-Result -Msg "Service StartMode is Automatic (Delayed Start)" -Success $isAutoDelayed
    if (-not $isAutoDelayed) {
        Write-Host "[DEBUG] StartMode: '$startMode', DelayedAutoStart: $delayed" -ForegroundColor Yellow
    }
    $isLocalSystem = ($logonAs.Trim() -eq "LocalSystem")
    Write-Result -Msg "Service Log On As is Local System" -Success $isLocalSystem
    if (-not $isLocalSystem) {
        Write-Host "[DEBUG] StartName: '$logonAs'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to query service properties" -Success $false
    Write-Host "[DEBUG] $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. Verify log file exists
Write-Host "Verifying log file $expectedLogFile exists..." -ForegroundColor Cyan
$logFilePath = Join-Path $logFolder $expectedLogFile
$logExists = Test-Path $logFilePath
Write-Result -Msg "$expectedLogFile exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file path: $logFilePath" -ForegroundColor Yellow
}

# 5. Verify scheduled task exists
Write-Host "Verifying scheduled task exists..." -ForegroundColor Cyan
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction Stop
    $taskFound = ($task -ne $null)
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $taskFound
    if (-not $taskFound) {
        Write-Host "[DEBUG] Scheduled task not found at $scheduledTaskPath" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' not found" -Success $false
    Write-Host "[DEBUG] $($_.Exception.Message)" -ForegroundColor Yellow
}

# 6. Verify WMI namespace exists (no "Invalid namespace" error)
Write-Host "Verifying WMI namespace $wmiNamespace exists..." -ForegroundColor Cyan
try {
    $wmiObj = Get-WmiObject -Namespace $wmiNamespace -List -ErrorAction Stop
    $wmiSuccess = ($wmiObj -ne $null)
    Write-Result -Msg "WMI namespace $wmiNamespace is valid" -Success $wmiSuccess
    if (-not $wmiSuccess) {
        Write-Host "[DEBUG] WMI namespace $wmiNamespace not found" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "WMI namespace $wmiNamespace is invalid" -Success $false
    Write-Host "[DEBUG] $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Uninstalling $productName silently..." -ForegroundColor Cyan

$uninstallExit = $null
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
    $uninstallExit = $uninstallProc.ExitCode
} catch {
    Write-Host "[FAIL] msiexec uninstall failed to start - $($_.Exception.Message)" -ForegroundColor Red
    $script:FailCount++
    $uninstallExit = $null
}

if ($uninstallExit -eq 0 -or $uninstallExit -eq 3010) {
    Write-Result -Msg "MSI uninstall succeeded (exit code $uninstallExit)" -Success $true
} elseif ($uninstallExit -eq 1605) {
    Write-Result -Msg "MSI uninstall: product not installed (exit code $uninstallExit)" -Success $true
} else {
    Write-Result -Msg "MSI uninstall failed (exit code $uninstallExit)" -Success $false
    Write-Host "[DEBUG] See uninstall log: $installLog" -ForegroundColor Yellow
}

# Verify service removed
$svcAfter = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
Write-Result -Msg "Service $serviceName removed after uninstall" -Success ($svcAfter -eq $null)
if ($svcAfter) {
    Write-Host "[DEBUG] Service still present after uninstall. Status: $($svcAfter.Status)" -ForegroundColor Yellow
}

# Verify product removed from installed programs
$foundProductAfter = Is-ProductInstalled -displayName $productName
Write-Result -Msg "$productName removed from installed programs" -Success (-not $foundProductAfter)
if ($foundProductAfter) {
    Write-Host "[DEBUG] Product still present in uninstall registry after uninstall" -ForegroundColor Yellow
}

# ============================================================
# SUMMARY AND ENDING
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