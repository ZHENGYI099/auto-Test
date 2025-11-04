# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case1testclient_$timestamp.log"

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

# MSI property reader (DO NOT MODIFY)
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
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
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

# Check MSI existence
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product already installed
function Get-InstalledProduct {
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

$alreadyInstalled = Get-InstalledProduct -displayName $productName
if ($alreadyInstalled) {
    Write-Result -Msg "$productName is already installed - uninstalling before test" -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation - ExitCode $($uninstallProc.ExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installCmd = "msiexec.exe /i `"$msiPath`" /qn"
Write-Host "Installing MSI silently..." -ForegroundColor Cyan
try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $installProc.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 3010)
    Write-Result -Msg "MSI installation exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] Installation failed - ExitCode $exitCode" -ForegroundColor Yellow
        Write-Host "Attempting verbose install for log collection..." -ForegroundColor Yellow
        $verboseLog = Join-Path $logDir "cmdextension_verbose_$timestamp.log"
        $null = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn /l*v `"$verboseLog`"" -Wait -PassThru
        Write-Host "Verbose log saved to $verboseLog" -ForegroundColor Yellow
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to appear (max 30s)
$serviceFound = $false
for ($i=0; $i -lt 30; $i++) {
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        $serviceFound = $true
        break
    }
    Start-Sleep -Seconds 1
}
Write-Result -Msg "Service $serviceName detected after install" -Success $serviceFound

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verify product in installed programs
$foundProduct = Get-InstalledProduct -displayName $productName
Write-Result -Msg "$productName present in installed programs" -Success $foundProduct

# 2. Verify service running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service $serviceName is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status - $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service $serviceName not found" -Success $false
}

# 3. Verify service properties (StartupType, LogOnAs)
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $startupType = $svcWmi.StartMode.Trim()
    $logOnAs = $svcWmi.StartName.Trim()
    $expectedStartup = "Delayed Auto"
    $expectedLogon = "LocalSystem"
    $startupMatch = ($startupType -eq $expectedStartup)
    $logonMatch = ($logOnAs -eq $expectedLogon)
    Write-Result -Msg "Service StartupType is $expectedStartup" -Success $startupMatch
    if (-not $startupMatch) {
        Write-Host "[DEBUG] Expected: '$expectedStartup', Actual: '$startupType'" -ForegroundColor Yellow
    }
    Write-Result -Msg "Service LogOnAs is $expectedLogon" -Success $logonMatch
    if (-not $logonMatch) {
        Write-Host "[DEBUG] Expected: '$expectedLogon', Actual: '$logOnAs'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to query service properties for $serviceName" -Success $false
}

# 4. Verify log file exists
$logPath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logPath
Write-Result -Msg "$logFileName exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file not found at $logPath" -ForegroundColor Yellow
}

# 5. Verify scheduled task exists
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName "Cloud Managed Desktop Extension Health Evaluation" -ErrorAction Stop
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' exists" -Success $true
} catch {
    Write-Result -Msg "Scheduled task 'Cloud Managed Desktop Extension Health Evaluation' missing" -Success $false
}

# 6. Verify WMI namespace exists (no "Invalid namespace" error)
try {
    $wmiObj = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
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

Write-Host "Uninstalling product..." -ForegroundColor Cyan
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 1605)
    Write-Result -Msg "MSI uninstall exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] Uninstall failed - ExitCode $exitCode" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
}

# Verify service removed
$svcAfter = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
$svcRemoved = ($svcAfter -eq $null)
Write-Result -Msg "Service $serviceName removed after uninstall" -Success $svcRemoved
if (-not $svcRemoved) {
    Write-Host "[DEBUG] Service still present after uninstall" -ForegroundColor Yellow
}

# Verify product removed from installed programs
$foundProductAfter = Get-InstalledProduct -displayName $productName
Write-Result -Msg "$productName removed from installed programs" -Success (-not $foundProductAfter)
if ($foundProductAfter) {
    Write-Host "[DEBUG] Product still present after uninstall" -ForegroundColor Yellow
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