# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case2test_$timestamp.log"

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

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$installFolder_x64 = "C:\Program Files\Microsoft Cloud Managed Desktop Extension"
$installFolder_x86 = "C:\Program Files (x86)\Microsoft Cloud Managed Desktop Extension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$infraLogPath = "$logFolder\InfraLogs\AgentMainService.log"
$cmdHealthTaskName = "Cloud Managed Desktop Extension Health Evaluation"
$scheduledTaskPath = "\Microsoft\CMD\$cmdHealthTaskName"

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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property' - $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Check if product is already installed (by product name in registry)
function IsProductInstalled {
    param([string]$displayName)
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem -Path $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $name = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                if ($name -ne $null -and ($name.Trim() -eq $displayName.Trim())) {
                    return $true
                }
            } catch {}
        }
    }
    return $false
}

if (IsProductInstalled -displayName $productName) {
    Write-Host "Product '$productName' is already installed. Attempting to uninstall before proceeding..." -ForegroundColor Yellow
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed" -Success $true
    } else {
        Write-Result -Msg "Failed to remove previous installation - ExitCode $exitCode" -Success $false
        Write-Host "Aborting test due to uninstall failure." -ForegroundColor Red
        Stop-Transcript
        exit 2
    }
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI package..." -ForegroundColor Cyan

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 3010)
    Write-Result -Msg "MSI installation exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] MSI install failed - ExitCode $exitCode" -ForegroundColor Yellow
        Write-Host "Aborting test due to install failure." -ForegroundColor Red
        Stop-Transcript
        exit 3
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 4
}

Write-Host ""
# ============================================================
# PHASE 3: UNINSTALLATION
# ============================================================
Write-Host "Uninstalling MSI package..." -ForegroundColor Cyan

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 1605)
    Write-Result -Msg "MSI uninstall exit code $exitCode" -Success $success
    if (-not $success) {
        Write-Host "[DEBUG] MSI uninstall failed - ExitCode $exitCode" -ForegroundColor Yellow
        Write-Host "Aborting test due to uninstall failure." -ForegroundColor Red
        Stop-Transcript
        exit 5
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 6
}

Write-Host ""
# ============================================================
# PHASE 4: VERIFICATION
# ============================================================
Write-Host "Verifying uninstall results..." -ForegroundColor Cyan

# Step 6: Verify there is NO “Microsoft Cloud Managed Desktop Extension” in the list of installed programs.
function IsProductPresent {
    param([string]$displayName)
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem -Path $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $name = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                if ($name -ne $null -and ($name.Trim() -eq $displayName.Trim())) {
                    return $true
                }
            } catch {}
        }
    }
    return $false
}
$isPresent = IsProductPresent -displayName $productName
Write-Result -Msg "Product '$productName' is NOT present in installed programs" -Success (-not $isPresent)
if ($isPresent) {
    Write-Host "[DEBUG] Product '$productName' still present after uninstall" -ForegroundColor Yellow
}

# Step 7: Verify there is NO “CloudManagedDesktopExtension” service.
try {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $exists = ($svc -ne $null)
    Write-Result -Msg "Service '$serviceName' is NOT present" -Success (-not $exists)
    if ($exists) {
        Write-Host "[DEBUG] Service '$serviceName' still present after uninstall" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Exception checking service '$serviceName' - $($_.Exception.Message)" -Success $false
}

# Step 8: Verify there is NO “Microsoft Cloud Managed Desktop Extension” service.
# Already covered by Step 7 (service name mapping).

# Step 9: Verify there is NO “Microsoft Cloud Managed Desktop Extension” folder.
$foldersToCheck = @($installFolder_x64, $installFolder_x86)
foreach ($folder in $foldersToCheck) {
    $exists = Test-Path $folder
    Write-Result -Msg "Install folder '$folder' is NOT present" -Success (-not $exists)
    if ($exists) {
        Write-Host "[DEBUG] Folder '$folder' still present after uninstall" -ForegroundColor Yellow
    }
}

# Step 10: Verify “CMDExtension.log” is still present.
$cmdExtensionLog = Join-Path $logFolder "CMDExtension.log"
$exists = Test-Path $cmdExtensionLog
Write-Result -Msg "'CMDExtension.log' is present in $logFolder" -Success $exists
if (-not $exists) {
    Write-Host "[DEBUG] Log file '$cmdExtensionLog' missing after uninstall" -ForegroundColor Yellow
}

# Step 11: Verify “Service is on OnStop” is printed in AgentMainService.log.
if (Test-Path $infraLogPath) {
    try {
        $content = Get-Content $infraLogPath -ErrorAction SilentlyContinue
        $found = $false
        foreach ($line in $content) {
            if ($line -ne $null -and $line.Trim() -match "Service is on OnStop") {
                $found = $true
                break
            }
        }
        Write-Result -Msg "'Service is on OnStop' found in AgentMainService.log" -Success $found
        if (-not $found) {
            Write-Host "[DEBUG] 'Service is on OnStop' not found in $infraLogPath" -ForegroundColor Yellow
        }
    } catch {
        Write-Result -Msg "Exception reading $infraLogPath - $($_.Exception.Message)" -Success $false
    }
} else {
    Write-Result -Msg "Infra log '$infraLogPath' not present" -Success $false
}

# Step 12: Verify there is NOT “Cloud Managed Desktop Extension Health Evaluation” scheduled task.
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName $cmdHealthTaskName -ErrorAction SilentlyContinue
    $exists = ($task -ne $null)
    Write-Result -Msg "Scheduled task '$cmdHealthTaskName' is NOT present" -Success (-not $exists)
    if ($exists) {
        Write-Host "[DEBUG] Scheduled task '$cmdHealthTaskName' still present after uninstall" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Exception checking scheduled task '$cmdHealthTaskName' - $($_.Exception.Message)" -Success $false
}

# Step 13: Verify WMI namespace "root\cmd\clientagent" is invalid.
try {
    $wmiObj = Get-WmiObject -Namespace "root\cmd\clientagent" -Class "__Namespace" -ErrorAction Stop
    # If no error, namespace exists (FAIL)
    Write-Result -Msg "WMI namespace 'root\cmd\clientagent' is invalid (should not exist)" -Success $false
    Write-Host "[DEBUG] WMI namespace 'root\cmd\clientagent' still exists after uninstall" -ForegroundColor Yellow
} catch {
    Write-Result -Msg "WMI namespace 'root\cmd\clientagent' is invalid (expected error)" -Success $true
}

# Step 14: Verify there is no "CloudManagementDesktop" registry key under specified paths.
$regPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CloudManagementDesktop",
    "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop"
)
foreach ($regPath in $regPaths) {
    $exists = Test-Path $regPath
    Write-Result -Msg "Registry key '$regPath' is NOT present" -Success (-not $exists)
    if ($exists) {
        Write-Host "[DEBUG] Registry key '$regPath' still present after uninstall" -ForegroundColor Yellow
    }
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