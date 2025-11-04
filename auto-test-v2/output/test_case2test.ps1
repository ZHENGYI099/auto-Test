# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case2test_$timestamp.log"

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
    Write-Host "[FAIL] ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$installFolder_x64 = "C:\Program Files\Microsoft Cloud Managed Desktop Extension"
$installFolder_x86 = "C:\Program Files (x86)\Microsoft Cloud Managed Desktop Extension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logFolder "CMDExtension.log"
$agentLogPath = "$env:ProgramData\Microsoft\CMDExtension\Logs\InfraLogs\AgentMainService.log"
$scheduledTaskName = "Cloud Managed Desktop Extension Health Evaluation"
$scheduledTaskPath = "\Microsoft\CMD\$scheduledTaskName"
$wmiNamespace = "root\cmd\clientagent"
$regPath_x64 = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop"
$regPath_x86 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CloudManagementDesktop"

# Check if product is already installed
function Get-ProductCode {
    param([string]$msiFile)
    $msi = New-Object -ComObject WindowsInstaller.Installer
    $db = $msi.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $msi, @($msiFile, 0))
    $view = $db.GetType().InvokeMember("OpenView", 'InvokeMethod', $null, $db, @("SELECT * FROM Property WHERE Property = 'ProductCode'"))
    $view.GetType().InvokeMember("Execute", 'InvokeMethod', $null, $view, $null)
    $record = $view.GetType().InvokeMember("Fetch", 'InvokeMethod', $null, $view, $null)
    if ($record -ne $null) {
        $productCode = $record.GetType().InvokeMember("StringData", 'GetProperty', $null, $record, 2)
        return $productCode
    }
    return $null
}

$productCode = Get-ProductCode -msiFile $msiPath
$alreadyInstalled = $false
if ($productCode) {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $productCode }
    if ($installed) {
        $alreadyInstalled = $true
        Write-Result -Msg "Product already installed: $productName ($productCode)" -Success $false
        Write-Host "Attempting to uninstall before test..." -ForegroundColor Yellow
        $uninstallCmd = "msiexec.exe /x $productCode /qn"
        $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $productCode /qn" -Wait -PassThru
        if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
            Write-Result -Msg "Pre-existing product uninstalled successfully." -Success $true
        } else {
            Write-Result -Msg "Failed to uninstall pre-existing product. Exit code: $($uninstallProc.ExitCode)" -Success $false
            Stop-Transcript
            exit 1
        }
    } else {
        Write-Result -Msg "Product not installed. Ready for test." -Success $true
    }
} else {
    Write-Result -Msg "Could not determine ProductCode from MSI. Proceeding with install." -Success $true
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing $productName from $msiPath ..." -ForegroundColor Cyan

$installCmd = "msiexec.exe /i `"$msiPath`" /qn"
try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $installProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installation succeeded. Exit code: $exitCode" -Success $true
    } else {
        Write-Result -Msg "MSI installation failed. Exit code: $exitCode" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 120

Write-Host ""
# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying installation artifacts..." -ForegroundColor Cyan

# 1. Service running?
try {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Result -Msg "Service '$serviceName' is running." -Success $true
    } elseif ($svc) {
        Write-Result -Msg "Service '$serviceName' exists but is not running." -Success $false
    } else {
        Write-Result -Msg "Service '$serviceName' not found." -Success $false
    }
} catch {
    Write-Result -Msg "Error checking service '$serviceName': $_" -Success $false
}

# 2. Service properties
try {
    $svcWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
    if ($svcWmi) {
        Write-Result -Msg "Service '$serviceName' properties found." -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' properties not found." -Success $false
    }
} catch {
    Write-Result -Msg "Error querying Win32_Service for '$serviceName': $_" -Success $false
}

# 3. Files created?
$folderExists_x64 = Test-Path $installFolder_x64
$folderExists_x86 = Test-Path $installFolder_x86
if ($folderExists_x64 -or $folderExists_x86) {
    Write-Result -Msg "Install folder exists." -Success $true
} else {
    Write-Result -Msg "Install folder does not exist." -Success $false
}

if (Test-Path $logFilePath) {
    Write-Result -Msg "CMDExtension.log exists at $logFilePath." -Success $true
} else {
    Write-Result -Msg "CMDExtension.log missing at $logFilePath." -Success $false
}

if (Test-Path $agentLogPath) {
    Write-Result -Msg "AgentMainService.log exists at $agentLogPath." -Success $true
} else {
    Write-Result -Msg "AgentMainService.log missing at $agentLogPath." -Success $false
}

# 4. Registry entries
$regExists_x64 = Test-Path $regPath_x64
$regExists_x86 = Test-Path $regPath_x86
if ($regExists_x64 -or $regExists_x86) {
    Write-Result -Msg "Registry key for CloudManagementDesktop exists." -Success $true
} else {
    Write-Result -Msg "Registry key for CloudManagementDesktop does not exist." -Success $false
}

# 5. Scheduled tasks
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName $scheduledTaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Result -Msg "Scheduled task '$scheduledTaskName' exists." -Success $true
    } else {
        Write-Result -Msg "Scheduled task '$scheduledTaskName' not found." -Success $false
    }
} catch {
    Write-Result -Msg "Error querying scheduled task: $_" -Success $false
}

# 6. WMI namespace
try {
    $wmiTest = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction SilentlyContinue
    if ($wmiTest) {
        Write-Result -Msg "WMI namespace '$wmiNamespace' exists." -Success $true
    } else {
        Write-Result -Msg "WMI namespace '$wmiNamespace' not found." -Success $false
    }
} catch {
    Write-Result -Msg "Error querying WMI namespace '$wmiNamespace': $_" -Success $false
}

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Uninstalling $productName ..." -ForegroundColor Cyan

try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExit = $uninstallProc.ExitCode
    if ($uninstallExit -eq 0 -or $uninstallExit -eq 1605) {
        Write-Result -Msg "MSI uninstallation succeeded. Exit code: $uninstallExit" -Success $true
    } elseif ($uninstallExit -eq 3010) {
        Write-Result -Msg "MSI uninstallation succeeded (reboot required). Exit code: $uninstallExit" -Success $true
    } else {
        Write-Result -Msg "MSI uninstallation failed. Exit code: $uninstallExit" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstallation: $_" -Success $false
}

Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Verifying cleanup..." -ForegroundColor Cyan

# 1. Service removed
try {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Result -Msg "Service '$serviceName' still exists after uninstall." -Success $false
    } else {
        Write-Result -Msg "Service '$serviceName' removed after uninstall." -Success $true
    }
} catch {
    Write-Result -Msg "Error checking service after uninstall: $_" -Success $false
}

# 2. Install folder removed
$folderExists_x64 = Test-Path $installFolder_x64
$folderExists_x86 = Test-Path $installFolder_x86
if (-not $folderExists_x64 -and -not $folderExists_x86) {
    Write-Result -Msg "Install folder removed after uninstall." -Success $true
} else {
    Write-Result -Msg "Install folder still exists after uninstall." -Success $false
}

# 3. Registry key removed
$regExists_x64 = Test-Path $regPath_x64
$regExists_x86 = Test-Path $regPath_x86
if (-not $regExists_x64 -and -not $regExists_x86) {
    Write-Result -Msg "Registry key removed after uninstall." -Success $true
} else {
    Write-Result -Msg "Registry key still exists after uninstall." -Success $false
}

# 4. Scheduled task removed
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName $scheduledTaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Result -Msg "Scheduled task '$scheduledTaskName' still exists after uninstall." -Success $false
    } else {
        Write-Result -Msg "Scheduled task '$scheduledTaskName' removed after uninstall." -Success $true
    }
} catch {
    Write-Result -Msg "Error querying scheduled task after uninstall: $_" -Success $false
}

# 5. WMI namespace removed
try {
    $wmiTest = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction SilentlyContinue
    if ($wmiTest) {
        Write-Result -Msg "WMI namespace '$wmiNamespace' still exists after uninstall." -Success $false
    } else {
        Write-Result -Msg "WMI namespace '$wmiNamespace' removed after uninstall." -Success $true
    }
} catch {
    Write-Result -Msg "Error querying WMI namespace after uninstall: $_" -Success $false
}

# 6. CMDExtension.log should still be present
if (Test-Path $logFilePath) {
    Write-Result -Msg "CMDExtension.log still present after uninstall." -Success $true
} else {
    Write-Result -Msg "CMDExtension.log missing after uninstall." -Success $false
}

# 7. AgentMainService.log should contain "Service is on OnStop"
if (Test-Path $agentLogPath) {
    $logContent = Get-Content $agentLogPath -ErrorAction SilentlyContinue
    if ($logContent -match "Service is on OnStop") {
        Write-Result -Msg "AgentMainService.log contains 'Service is on OnStop'." -Success $true
    } else {
        Write-Result -Msg "AgentMainService.log does NOT contain 'Service is on OnStop'." -Success $false
    }
} else {
    Write-Result -Msg "AgentMainService.log missing after uninstall." -Success $false
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')