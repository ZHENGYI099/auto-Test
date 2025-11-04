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

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$productName = "Microsoft Cloud Managed Desktop Extension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFileName = "CMDExtension.log"
$logFilePath = Join-Path $logFolder $logFileName

# Helper: Get MSI property (per strict instructions)
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

# Helper: Get installed product code for MSI
function Get-InstalledProductCode {
    param([string]$msiPath)
    $productCode = Get-MSIProperty -msiPath $msiPath -property "ProductCode"
    if ($null -eq $productCode) { return $null }
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
    if (Test-Path $regPath) { return $productCode }
    $regPathWow = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
    if (Test-Path $regPathWow) { return $productCode }
    return $null
}

# Pre-check: Is product already installed?
$installedProductCode = Get-InstalledProductCode -msiPath $msiPath
if ($null -ne $installedProductCode) {
    Write-Host "ERROR - Product already installed. Uninstall before running this test." -ForegroundColor Red
    Stop-Transcript
    exit 2
}

Write-Host "Pre-checks passed. Proceeding with installation..." -ForegroundColor Cyan
Write-Host ""

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing MSI package silently..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" /qn"
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = "msiexec.exe"
$processInfo.Arguments = $installArgs
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

try {
    $null = $process.Start()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    Write-Host "MSI install exit code: $exitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "MSI installation process failed to start" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 3
}

# Validate exit code
$validInstallCodes = @(0, 3010)
if ($validInstallCodes -contains $exitCode) {
    Write-Result -Msg "MSI installed successfully (exit code $exitCode)" -Success $true
} elseif ($exitCode -eq 1603) {
    Write-Result -Msg "MSI installation failed - Fatal error (exit code 1603)" -Success $false
    Stop-Transcript
    exit 1603
} elseif ($exitCode -eq 1618) {
    Write-Result -Msg "MSI installation failed - Another installation in progress (exit code 1618)" -Success $false
    Stop-Transcript
    exit 1618
} elseif ($exitCode -eq 1925) {
    Write-Result -Msg "MSI installation failed - Insufficient privileges (exit code 1925)" -Success $false
    Stop-Transcript
    exit 1925
} else {
    Write-Result -Msg "MSI installation failed - Unknown error (exit code $exitCode)" -Success $false
    Stop-Transcript
    exit $exitCode
}

# Wait 1 minute as per test scenario
Write-Host "Waiting 1 minute before restart..." -ForegroundColor Cyan
Start-Sleep -Seconds 60

# Restart device (silent, force, no UI)
Write-Host "Restarting device now (silent)..." -ForegroundColor Cyan
try {
    Restart-Computer -Force
    # Script will terminate here due to restart
} catch {
    Write-Result -Msg "Device restart failed" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 4
}

# ============================================================
# PHASE 3: VERIFICATION (POST-RESTART)
# ============================================================
# NOTE: The following code should be run after device restarts.
# To automate, place this block in a separate script scheduled to run at startup,
# or instruct test runner to resume here after reboot.

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION (POST-RESTART)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 6: Verify "CloudManagedDesktopExtension" service is running
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    $isRunning = ($svc.Status -eq "Running")
    Write-Result -Msg "Service '$serviceName' is running" -Success $isRunning
    if (-not $isRunning) {
        Write-Host "[DEBUG] Expected: 'Running', Actual: '$($svc.Status)'" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 7: Verify service display name, status, startup type, logon account
try {
    $svcWMI = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $expectedDisplayName = $productName
    $expectedStatus = "Running"
    $expectedStartMode = "Auto"
    $expectedLogon = "LocalSystem"

    $actualDisplayName = $svcWMI.DisplayName
    $actualStatus = $svcWMI.State
    $actualStartMode = $svcWMI.StartMode
    $actualLogon = $svcWMI.StartName

    # Display Name
    if ([string]::IsNullOrWhiteSpace($actualDisplayName)) {
        Write-Result -Msg "Service display name is missing" -Success $false
    } else {
        $isDisplayName = ($actualDisplayName.Trim() -eq $expectedDisplayName)
        Write-Result -Msg "Service display name is '$expectedDisplayName'" -Success $isDisplayName
        if (-not $isDisplayName) {
            Write-Host "[DEBUG] Expected: '$expectedDisplayName', Actual: '$actualDisplayName'" -ForegroundColor Yellow
        }
    }
    # Status
    if ([string]::IsNullOrWhiteSpace($actualStatus)) {
        Write-Result -Msg "Service status is missing" -Success $false
    } else {
        $isStatus = ($actualStatus.Trim() -eq $expectedStatus)
        Write-Result -Msg "Service status is '$expectedStatus'" -Success $isStatus
        if (-not $isStatus) {
            Write-Host "[DEBUG] Expected: '$expectedStatus', Actual: '$actualStatus'" -ForegroundColor Yellow
        }
    }
    # Startup Type
    if ([string]::IsNullOrWhiteSpace($actualStartMode)) {
        Write-Result -Msg "Service startup type is missing" -Success $false
    } else {
        $isStartMode = ($actualStartMode.Trim() -eq $expectedStartMode)
        Write-Result -Msg "Service startup type is 'Automatic'" -Success $isStartMode
        if (-not $isStartMode) {
            Write-Host "[DEBUG] Expected: '$expectedStartMode', Actual: '$actualStartMode'" -ForegroundColor Yellow
        }
    }
    # Log On As
    if ([string]::IsNullOrWhiteSpace($actualLogon)) {
        Write-Result -Msg "Service logon account is missing" -Success $false
    } else {
        $isLogon = ($actualLogon.Trim() -eq $expectedLogon)
        Write-Result -Msg "Service logon account is 'Local System'" -Success $isLogon
        if (-not $isLogon) {
            Write-Host "[DEBUG] Expected: '$expectedLogon', Actual: '$actualLogon'" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Result -Msg "WMI query for service '$serviceName' failed" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 8: Verify log file contains at least 2 lines of "Start up args length: 0"
if (Test-Path $logFilePath) {
    try {
        $logLines = Get-Content -Path $logFilePath -ErrorAction Stop
        if ($null -eq $logLines) {
            Write-Result -Msg "Log file '$logFilePath' is empty" -Success $false
        } else {
            $matchCount = ($logLines | Where-Object { 
                if ([string]::IsNullOrWhiteSpace($_)) { $false } else { $_.Trim() -eq "Start up args length: 0" }
            }).Count
            $isAtLeastTwo = ($matchCount -ge 2)
            Write-Result -Msg "Log file contains at least 2 lines of 'Start up args length: 0'" -Success $isAtLeastTwo
            if (-not $isAtLeastTwo) {
                Write-Host "[DEBUG] Found $matchCount lines. Expected at least 2." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Result -Msg "Failed to read log file '$logFilePath'" -Success $false
        Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Result -Msg "Log file '$logFilePath' does not exist" -Success $false
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn"
$processInfoUn = New-Object System.Diagnostics.ProcessStartInfo
$processInfoUn.FileName = "msiexec.exe"
$processInfoUn.Arguments = $uninstallArgs
$processInfoUn.UseShellExecute = $false
$processInfoUn.RedirectStandardOutput = $true
$processInfoUn.RedirectStandardError = $true

$processUn = New-Object System.Diagnostics.Process
$processUn.StartInfo = $processInfoUn

try {
    $null = $processUn.Start()
    $processUn.WaitForExit()
    $unExitCode = $processUn.ExitCode
    Write-Host "MSI uninstall exit code: $unExitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "MSI uninstall process failed to start" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 5
}

# Validate uninstall exit code
$validUninstallCodes = @(0, 3010, 1605)
if ($validUninstallCodes -contains $unExitCode) {
    Write-Result -Msg "MSI uninstalled successfully (exit code $unExitCode)" -Success $true
} elseif ($unExitCode -eq 1603) {
    Write-Result -Msg "MSI uninstall failed - Fatal error (exit code 1603)" -Success $false
    Stop-Transcript
    exit 1603
} elseif ($unExitCode -eq 1618) {
    Write-Result -Msg "MSI uninstall failed - Another installation in progress (exit code 1618)" -Success $false
    Stop-Transcript
    exit 1618
} elseif ($unExitCode -eq 1925) {
    Write-Result -Msg "MSI uninstall failed - Insufficient privileges (exit code 1925)" -Success $false
    Stop-Transcript
    exit 1925
} else {
    Write-Result -Msg "MSI uninstall failed - Unknown error (exit code $unExitCode)" -Success $false
    Stop-Transcript
    exit $unExitCode
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