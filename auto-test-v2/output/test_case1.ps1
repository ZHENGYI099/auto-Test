# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case1_$timestamp.log"

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
    exit 1
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFileName = "CMDExtension.log"
$scheduledTaskName = "Cloud Managed Desktop Extension Health Evaluation"
$scheduledTaskPath = "\Microsoft\CMD\$scheduledTaskName"
$wmiNamespace = "root\cmd\clientagent"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Write-Host "Aborting test due to missing MSI." -ForegroundColor Red
    Stop-Transcript
    exit 2
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product already installed (by DisplayName)
$alreadyInstalled = $false
try {
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $displayName = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            if ($null -ne $displayName -and $displayName.Trim() -eq $productName) {
                $alreadyInstalled = $true
                break
            }
        }
        if ($alreadyInstalled) { break }
    }
} catch {
    Write-Host "[DEBUG] Exception during product check - $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($alreadyInstalled) {
    Write-Result -Msg "$productName is already installed. Uninstall before running this test." -Success $false
    Write-Host "Aborting test due to pre-existing installation." -ForegroundColor Red
    Stop-Transcript
    exit 3
} else {
    Write-Result -Msg "$productName is not installed (pre-check passed)" -Success $true
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$msiLog = Join-Path $logDir "install_cmdextension_$timestamp.log"
$installCmd = "msiexec.exe /i `"$msiPath`" /qn /l*v `"$msiLog`""
Write-Host "Installing $productName..." -ForegroundColor Cyan
Write-Host "Running: $installCmd" -ForegroundColor Gray

$exitCode = $null
try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn /l*v `"$msiLog`"" -Wait -PassThru
    $exitCode = $process.ExitCode
} catch {
    Write-Host "[DEBUG] Exception during MSI install - $($_.Exception.Message)" -ForegroundColor Yellow
    $exitCode = -1
}

# Acceptable exit codes: 0 (success), 3010 (success, reboot required)
if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installation succeeded (exit code $exitCode)" -Success $true
} else {
    Write-Result -Msg "MSI installation failed (exit code $exitCode)" -Success $false
    Write-Host "[DEBUG] See install log at $msiLog" -ForegroundColor Yellow
    Write-Host "Aborting test due to install failure." -ForegroundColor Red
    Stop-Transcript
    exit 4
}

# Wait 10 seconds for service registration/startup
Start-Sleep -Seconds 10

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 5: Verify product in installed programs (Control Panel)
$foundProduct = $false
try {
    $foundProduct = $false
    foreach ($key in $uninstallKeys) {
        $items = Get-ChildItem $key -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $displayName = (Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            if ($null -ne $displayName -and $displayName.Trim() -eq $productName) {
                $foundProduct = $true
                break
            }
        }
        if ($foundProduct) { break }
    }
} catch {
    Write-Host "[DEBUG] Exception during installed programs check - $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Result -Msg "Product '$productName' is present in installed programs" -Success $foundProduct
if (-not $foundProduct) {
    Write-Host "[DEBUG] Product not found in uninstall registry keys" -ForegroundColor Yellow
}

# Step 6: Verify service is running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq 'Running')
    Write-Result -Msg "Service '$serviceName' is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status is '$($svc.Status)'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found" -Success $false
    Write-Host "[DEBUG] Exception during service check - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 7: Verify service details (Status, Startup Type, Log On As)
try {
    $wmiSvc = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $statusOk = ($null -ne $wmiSvc.State -and $wmiSvc.State.Trim() -eq "Running")
    $startupOk = ($null -ne $wmiSvc.StartMode -and $wmiSvc.StartMode.Trim() -eq "Auto")
    $delayedOk = $false
    if ($null -ne $wmiSvc.DelayedAutoStart) {
        $delayedOk = ($wmiSvc.DelayedAutoStart -eq $true)
    }
    $startupTypeOk = $startupOk -and $delayedOk
    $logonOk = ($null -ne $wmiSvc.StartName -and $wmiSvc.StartName.Trim() -eq "LocalSystem")
    Write-Result -Msg "Service '$serviceName' status is Running" -Success $statusOk
    if (-not $statusOk) {
        Write-Host "[DEBUG] Service state is '$($wmiSvc.State)'" -ForegroundColor Yellow
    }
    Write-Result -Msg "Service '$serviceName' startup type is Automatic (Delayed Start)" -Success $startupTypeOk
    if (-not $startupTypeOk) {
        Write-Host "[DEBUG] StartMode: '$($wmiSvc.StartMode)', DelayedAutoStart: '$($wmiSvc.DelayedAutoStart)'" -ForegroundColor Yellow
    }
    Write-Result -Msg "Service '$serviceName' Log On As is Local System" -Success $logonOk
    if (-not $logonOk) {
        Write-Host "[DEBUG] StartName is '$($wmiSvc.StartName)'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "WMI service object for '$serviceName' not found" -Success $false
    Write-Host "[DEBUG] Exception during WMI service check - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 8: Verify CMDExtension.log is present
$logPath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logPath
Write-Result -Msg "'$logFileName' exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file not found at $logPath" -ForegroundColor Yellow
}

# Step 9: Verify scheduled task exists
$taskExists = $false
try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\CMD\" -TaskName $scheduledTaskName -ErrorAction Stop
    $taskExists = $true
} catch {
    $taskExists = $false
}
Write-Result -Msg "Scheduled task '$scheduledTaskName' exists at path '\Microsoft\CMD\'" -Success $taskExists
if (-not $taskExists) {
    Write-Host "[DEBUG] Scheduled task not found at $scheduledTaskPath" -ForegroundColor Yellow
}

# Step 10: Verify WMI namespace exists (no 'Invalid namespace' error)
$wmiNamespaceOk = $true
try {
    $null = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
    $wmiNamespaceOk = $true
} catch {
    if ($_.Exception.Message -match "Invalid namespace") {
        $wmiNamespaceOk = $false
    } else {
        $wmiNamespaceOk = $false
        Write-Host "[DEBUG] Exception during WMI namespace check - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Result -Msg "WMI namespace '$wmiNamespace' exists (no 'Invalid namespace' error)" -Success $wmiNamespaceOk
if (-not $wmiNamespaceOk) {
    Write-Host "[DEBUG] WMI namespace '$wmiNamespace' is invalid or missing" -ForegroundColor Yellow
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn /l*v `"$msiLog`""
Write-Host "Uninstalling $productName..." -ForegroundColor Cyan
Write-Host "Running: $uninstallCmd" -ForegroundColor Gray

$uninstallExitCode = $null
try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn /l*v `"$msiLog`"" -Wait -PassThru
    $uninstallExitCode = $process.ExitCode
} catch {
    Write-Host "[DEBUG] Exception during MSI uninstall - $($_.Exception.Message)" -ForegroundColor Yellow
    $uninstallExitCode = -1
}

if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 3010 -or $uninstallExitCode -eq 1605) {
    Write-Result -Msg "MSI uninstall completed (exit code $uninstallExitCode)" -Success $true
} else {
    Write-Result -Msg "MSI uninstall failed (exit code $uninstallExitCode)" -Success $false
    Write-Host "[DEBUG] See uninstall log at $msiLog" -ForegroundColor Yellow
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