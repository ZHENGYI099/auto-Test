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

# Admin check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
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

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 2
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product already installed
$alreadyInstalled = $false
try {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }
    if ($installed) {
        $alreadyInstalled = $true
        Write-Result -Msg "$productName is already installed" -Success $false
    }
} catch {
    Write-Host "[DEBUG] Failed to query Win32_Product - $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($alreadyInstalled) {
    Write-Host "Uninstalling existing $productName before test..." -ForegroundColor Yellow
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "Previous $productName uninstalled" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous $productName - ExitCode $exitCode" -Success $false
        Stop-Transcript
        exit 3
    }
    Start-Sleep -Seconds 5
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installLog = Join-Path $logDir "cmdextension_install_$timestamp.log"
$installCmd = "msiexec.exe /i `"$msiPath`" /qn /l*v `"$installLog`""
Write-Host "Installing $productName..." -ForegroundColor Cyan
try {
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn /l*v `"$installLog`"" -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (ExitCode $exitCode)" -Success $true
    } else {
        Write-Result -Msg "MSI installation failed (ExitCode $exitCode)" -Success $false
        Write-Host "[DEBUG] See log: $installLog" -ForegroundColor Yellow
        Stop-Transcript
        exit 4
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 5
}

Start-Sleep -Seconds 5

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 5: Verify product in installed programs
try {
    $found = $false
    $products = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $productName }
    if ($products) {
        $found = $true
    }
    Write-Result -Msg "$productName present in installed programs" -Success $found
    if (-not $found) {
        Write-Host "[DEBUG] $productName not found in Win32_Product" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to query installed programs - $($_.Exception.Message)" -Success $false
}

# Step 6: Verify service is running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq 'Running')
    Write-Result -Msg "$serviceName service is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Service status: $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service $serviceName not found - $($_.Exception.Message)" -Success $false
}

# Step 7: Verify service properties (Status, StartupType, LogOnAs)
try {
    $svcWMI = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
    if ($null -eq $svcWMI) {
        Write-Result -Msg "WMI service $serviceName not found" -Success $false
    } else {
        $statusMatch = ($svcWMI.State.Trim() -eq "Running")
        Write-Result -Msg "$serviceName WMI State is Running" -Success $statusMatch
        if (-not $statusMatch) {
            Write-Host "[DEBUG] WMI State: '$($svcWMI.State)'" -ForegroundColor Yellow
        }
        $startupMatch = ($svcWMI.StartMode.Trim() -eq "Auto")
        $delayed = $false
        if ($svcWMI.DelayedAutoStart -ne $null) {
            $delayed = $svcWMI.DelayedAutoStart
        }
        $startupTypeMatch = $startupMatch -and $delayed
        Write-Result -Msg "$serviceName Startup Type is Automatic (Delayed Start)" -Success $startupTypeMatch
        if (-not $startupTypeMatch) {
            Write-Host "[DEBUG] StartMode: '$($svcWMI.StartMode)', DelayedAutoStart: '$($svcWMI.DelayedAutoStart)'" -ForegroundColor Yellow
        }
        $logonMatch = ($svcWMI.StartName.Trim() -eq "LocalSystem")
        Write-Result -Msg "$serviceName Log On As is Local System" -Success $logonMatch
        if (-not $logonMatch) {
            Write-Host "[DEBUG] StartName: '$($svcWMI.StartName)'" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Result -Msg "Failed to query WMI service properties - $($_.Exception.Message)" -Success $false
}

# Step 8: Verify log file exists
$logFilePath = Join-Path $logFolder $logFileName
$logExists = Test-Path $logFilePath
Write-Result -Msg "$logFileName exists in $logFolder" -Success $logExists
if (-not $logExists) {
    Write-Host "[DEBUG] Log file not found at $logFilePath" -ForegroundColor Yellow
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
    Write-Host "[DEBUG] Scheduled task not found: $scheduledTaskPath" -ForegroundColor Yellow
}

# Step 10: Verify WMI namespace exists (no Invalid namespace error)
try {
    $null = Get-WmiObject -Namespace $wmiNamespace -Class "__Namespace" -ErrorAction Stop
    Write-Result -Msg "WMI namespace $wmiNamespace exists (no Invalid namespace error)" -Success $true
} catch {
    Write-Result -Msg "WMI namespace $wmiNamespace is INVALID" -Success $false
    Write-Host "[DEBUG] Exception: $($_.Exception.Message)" -ForegroundColor Yellow
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
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn /l*v `"$installLog`"" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "$productName uninstalled successfully (ExitCode $exitCode)" -Success $true
    } else {
        Write-Result -Msg "Uninstall failed (ExitCode $exitCode)" -Success $false
        Write-Host "[DEBUG] See log: $installLog" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Exception during uninstall - $($_.Exception.Message)" -Success $false
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