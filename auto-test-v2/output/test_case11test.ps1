# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case11test_$timestamp.log"

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

# Helper function for result tracking
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

# Define MSI paths and product/service names
$msiV1Path = "C:\VMShare\cmdextension.v1.msi"
$msiV2Path = "C:\VMShare\cmdextension.v2.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFilePath = "C:\ProgramData\CloudManagedDesktopExtension\CMDExtension.log"

# Check if MSI files exist
if (-not (Test-Path $msiV1Path)) {
    Write-Result -Msg "MSI v1 file not found: $msiV1Path" -Success $false
    Stop-Transcript
    exit 1
}
if (-not (Test-Path $msiV2Path)) {
    Write-Result -Msg "MSI v2 file not found: $msiV2Path" -Success $false
    Stop-Transcript
    exit 1
}

# Check if product is already installed (by service existence)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service '$serviceName' already installed. Attempting to uninstall for clean test..." -Success $false
    # Try uninstalling both versions
    $uninstallCmd = "msiexec.exe /x `"$msiV1Path`" /qn"
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiV1Path`" /qn" -Wait -PassThru).ExitCode
    Start-Sleep -Seconds 10
    $exitCode2 = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiV2Path`" /qn" -Wait -PassThru).ExitCode
    Start-Sleep -Seconds 10
    # Check if service is gone
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $serviceExists) {
        Write-Result -Msg "Previous installation cleaned up." -Success $true
    } else {
        Write-Result -Msg "Failed to clean previous installation. Manual cleanup required." -Success $false
        Stop-Transcript
        exit 1
    }
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION (v1)
# ============================================================
Write-Host "Installing agent v1..." -ForegroundColor Cyan

try {
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiV1Path`" /qn SVCENV=`"Test`"" -Wait -PassThru).ExitCode
    Write-Host "MSI v1 install exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI v1 installed successfully (exit code $exitCode)" -Success $true
    } else {
        Write-Result -Msg "MSI v1 installation failed (exit code $exitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI v1 installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for agent to initialize
Start-Sleep -Seconds 60

# ============================================================
# PHASE 3: VERIFICATION (v1)
# ============================================================
Write-Host "Verifying agent v1 installation..." -ForegroundColor Cyan

# 1. Check CMDExtension.log for "DeviceClient created and opened successfully"
$logFound = $false
if (Test-Path $logFilePath) {
    $logContent = Get-Content $logFilePath -ErrorAction SilentlyContinue
    if ($logContent -match "DeviceClient created and opened successfully") {
        $logFound = $true
    }
}
Write-Result -Msg "CMDExtension.log contains 'DeviceClient created and opened successfully'" -Success $logFound

# 2. WMI Table Check
try {
    $sc = Get-WmiObject -Namespace "root/cmd/clientagent" -Class SchedulerEntity -ErrorAction Stop
    $test1 = @()
    for ($i=0; $i -lt $sc.Length; $i++) {
        $test1 += $sc[$i].PolicyId
    }
    $test2 = $test1 | Select-Object -Unique
    $wmiCheck = ($test1.Length -eq $test2.Length)
    Write-Result -Msg "WMI SchedulerEntity PolicyId uniqueness check (v1)" -Success $wmiCheck
} catch {
    Write-Result -Msg "WMI query failed (v1): $_" -Success $false
}

# ============================================================
# PHASE 2: UPGRADE INSTALLATION (v2)
# ============================================================
Write-Host "Upgrading agent to v2..." -ForegroundColor Cyan

try {
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiV2Path`" /qn SVCENV=`"Test`"" -Wait -PassThru).ExitCode
    Write-Host "MSI v2 install exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI v2 installed/upgraded successfully (exit code $exitCode)" -Success $true
    } else {
        Write-Result -Msg "MSI v2 installation/upgrade failed (exit code $exitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI v2 installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for agent to initialize
Start-Sleep -Seconds 60

# ============================================================
# PHASE 3: VERIFICATION (v2)
# ============================================================
Write-Host "Verifying agent v2 installation..." -ForegroundColor Cyan

# 1. Check CMDExtension.log for "DeviceClient created and opened successfully"
$logFound = $false
if (Test-Path $logFilePath) {
    $logContent = Get-Content $logFilePath -ErrorAction SilentlyContinue
    if ($logContent -match "DeviceClient created and opened successfully") {
        $logFound = $true
    }
}
Write-Result -Msg "CMDExtension.log contains 'DeviceClient created and opened successfully' (v2)" -Success $logFound

# 2. WMI Table Check
try {
    $sc = Get-WmiObject -Namespace "root/cmd/clientagent" -Class SchedulerEntity -ErrorAction Stop
    $test1 = @()
    for ($i=0; $i -lt $sc.Length; $i++) {
        $test1 += $sc[$i].PolicyId
    }
    $test2 = $test1 | Select-Object -Unique
    $wmiCheck = ($test1.Length -eq $test2.Length)
    Write-Result -Msg "WMI SchedulerEntity PolicyId uniqueness check (v2)" -Success $wmiCheck
} catch {
    Write-Result -Msg "WMI query failed (v2): $_" -Success $false
}

# 3. Verify product is present and version is v2
# Get installed product version from registry
function Get-MSIProductVersion {
    param([string]$msiPath)
    $msiName = Split-Path $msiPath -Leaf
    $productCode = ""
    # Try to extract ProductCode from MSI
    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $windowsInstaller, @($msiPath, 0))
        $view = $database.GetType().InvokeMember("OpenView", 'InvokeMethod', $null, $database, @("SELECT * FROM Property WHERE Property = 'ProductCode'"))
        $view.GetType().InvokeMember("Execute", 'InvokeMethod', $null, $view, $null)
        $record = $view.GetType().InvokeMember("Fetch", 'InvokeMethod', $null, $view, $null)
        if ($record) {
            $productCode = $record.GetType().InvokeMember("StringData", 'GetProperty', $null, $record, 2)
        }
    } catch {
        $productCode = ""
    }
    if ($productCode) {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
        if (Test-Path $regPath) {
            $props = Get-ItemProperty $regPath
            return $props.DisplayVersion
        }
    }
    return $null
}

$v2Version = Get-MSIProductVersion -msiPath $msiV2Path
$foundVersion = $null
# Search in registry for installed product
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
$found = $false
foreach ($path in $uninstallPaths) {
    $keys = Get-ChildItem $path -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
        if ($props.DisplayName -eq $productName) {
            $found = $true
            $foundVersion = $props.DisplayVersion
            break
        }
    }
    if ($found) { break }
}
if ($found -and $foundVersion -eq $v2Version) {
    Write-Result -Msg "Product '$productName' is present with version $foundVersion (expected v2)" -Success $true
} elseif ($found) {
    Write-Result -Msg "Product '$productName' is present but version mismatch: $foundVersion (expected $v2Version)" -Success $false
} else {
    Write-Result -Msg "Product '$productName' not found in installed programs" -Success $false
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling agent v2..." -ForegroundColor Cyan

try {
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiV2Path`" /qn" -Wait -PassThru).ExitCode
    Write-Host "MSI v2 uninstall exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1605) {
        Write-Result -Msg "MSI v2 uninstalled successfully (exit code $exitCode)" -Success $true
    } else {
        Write-Result -Msg "MSI v2 uninstall failed (exit code $exitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI v2 uninstall: $_" -Success $false
}

# Verify service is removed
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $serviceExists) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still present after uninstall" -Success $false
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