# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case3test_$timestamp.log"

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
} else {
    Write-Result -Msg "Running as Administrator" -Success $true
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$productName = "Microsoft Cloud Managed Desktop Extension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logFolder "CMDExtension.log"

# Check if MSI file exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed
$installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }
if ($installed) {
    Write-Result -Msg "Product '$productName' is already installed. Uninstalling before test..." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProc.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed (exit code: $uninstallExitCode)" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (exit code: $uninstallExitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} else {
    Write-Result -Msg "Product '$productName' is not installed. Proceeding..." -Success $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI package silently..." -ForegroundColor Cyan

try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $installProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installation succeeded (exit code: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (exit code: 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation failed (exit code: $exitCode)" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (give it up to 60 seconds)
Write-Host "Waiting for service '$serviceName' to start..." -ForegroundColor Cyan
$serviceStarted = $false
for ($i=0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 5
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $serviceStarted = $true
        break
    }
}
Write-Result -Msg "Service '$serviceName' running after installation" -Success $serviceStarted

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
# 1. Verify service is running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Result -Msg "Service '$serviceName' is in running state" -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' is NOT running (status: $($svc.Status))" -Success $false
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found" -Success $false
}

# 2. Verify service properties: Status=Running, StartupType=Automatic, LogOnAs=LocalSystem
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $startupType = $svcWmi.StartMode
    $logonAs = $svcWmi.StartName
    $status = $svcWmi.State

    Write-Result -Msg "Service '$productName' status is '$status'" -Success ($status -eq "Running")
    Write-Result -Msg "Service '$productName' startup type is '$startupType'" -Success ($startupType -eq "Auto")
    Write-Result -Msg "Service '$productName' Log On As is '$logonAs'" -Success ($logonAs -eq "LocalSystem")
} catch {
    Write-Result -Msg "Failed to get service properties for '$productName'" -Success $false
}

# 3. Verify log file exists
if (Test-Path $logFilePath) {
    Write-Result -Msg "Log file exists at $logFilePath" -Success $true
} else {
    Write-Result -Msg "Log file does NOT exist at $logFilePath" -Success $false
}

# 4. Verify at least 2 lines of "Start up args length: 0" in the log
$startupArgsCount = 0
if (Test-Path $logFilePath) {
    try {
        $startupArgsCount = (Select-String -Path $logFilePath -Pattern "Start up args length: 0").Count
        Write-Result -Msg "Log file contains $startupArgsCount lines of 'Start up args length: 0'" -Success ($startupArgsCount -ge 2)
    } catch {
        Write-Result -Msg "Error reading log file for 'Start up args length: 0'" -Success $false
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling MSI package silently..." -ForegroundColor Cyan

try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProc.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstallation succeeded (exit code: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstallation failed (exit code: 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstallation failed (exit code: $uninstallExitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstallation: $_" -Success $false
}

# Optional: Verify service is removed
$svcAfterUninstall = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svcAfterUninstall) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still exists after uninstall" -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "[PASS] All test steps passed." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Some test steps failed. See log for details." -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')