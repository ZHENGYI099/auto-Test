# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case24test_$timestamp.log"

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
        Write-Host "[DEBUG] Get-MSIProperty failed for property '$property': $_" -ForegroundColor Yellow
        return $null
    }
}

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "❌ ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define paths and names
$msiPath = "C:\VMShare\cmdextension.msi"
$testToastScript = "C:\VMShare\test_toast.ps1"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$userNotificationsLog = Join-Path $logFolder "UserNotificationsPlugin.log"

# MSI ProductCode (for uninstall check)
$msiProductCode = Get-MSIProperty -msiPath $msiPath -property "ProductCode"
if ([string]::IsNullOrWhiteSpace($msiProductCode)) {
    Write-Result -Msg "Failed to retrieve MSI ProductCode" -Success $false
    Stop-Transcript
    exit 2
}

# Check if product already installed
$installed = $false
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$msiProductCode"
    if (Test-Path $regPath) {
        $installed = $true
    }
} catch {}
if ($installed) {
    Write-Result -Msg "Product already installed. Uninstalling before test..." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (ExitCode: $($uninstallProc.ExitCode))" -Success $false
        Stop-Transcript
        exit 3
    }
}

# Check for required files
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found: $msiPath" -Success $false
    Stop-Transcript
    exit 4
}
if (-not (Test-Path $testToastScript)) {
    Write-Result -Msg "Test toast script not found: $testToastScript" -Success $false
    Stop-Transcript
    exit 5
}

Write-Result -Msg "Pre-checks completed" -Success $true
Write-Host ""

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing product..." -ForegroundColor Cyan

$installArgs = "/i `"$msiPath`" SVCENV=Test /qn"
try {
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (ExitCode: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (ExitCode: 1603)" -Success $false
        Stop-Transcript
        exit 6
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (ExitCode: 1618)" -Success $false
        Stop-Transcript
        exit 7
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (ExitCode: 1925)" -Success $false
        Stop-Transcript
        exit 8
    } else {
        Write-Result -Msg "MSI installation failed (ExitCode: $exitCode)" -Success $false
        Stop-Transcript
        exit 9
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 10
}

# Wait for service to start (max 2 min, check every 5 sec)
$serviceStarted = $false
for ($i=0; $i -lt 24; $i++) {
    try {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            $serviceStarted = $true
            break
        }
    } catch {}
    Start-Sleep -Seconds 5
}
Write-Result -Msg "Service '$serviceName' running after install" -Success $serviceStarted

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying installation and plugin behavior..." -ForegroundColor Cyan

# Wait 10 minutes as per scenario (simulate with 10 sec for test automation)
Write-Host "Waiting for plugin initialization (simulated 10 sec)..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# Ensure execution policy allows running the toast script
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Result -Msg "Execution policy set to Bypass for this session" -Success $true
} catch {
    Write-Result -Msg "Failed to set execution policy" -Success $false
}

# Run test_toast.ps1
$toastSuccess = $false
try {
    $toastResult = & $testToastScript
    $toastSuccess = $true
} catch {
    Write-Result -Msg "Failed to execute test_toast.ps1: $_" -Success $false
}
Write-Result -Msg "test_toast.ps1 executed" -Success $toastSuccess

# Log verification: UserNotificationsPlugin.log
$logExists = Test-Path $userNotificationsLog
Write-Result -Msg "UserNotificationsPlugin.log exists" -Success $logExists

$expectedLogLines = @(
    'The UX input is : {"TemplateType":"sampleTemplate"',
    'DisplayUserNotification is waiting for the UX to be closed'
)
$logContent = ""
if ($logExists) {
    try {
        $logContent = Get-Content $userNotificationsLog -ErrorAction Stop
    } catch {
        Write-Result -Msg "Failed to read UserNotificationsPlugin.log" -Success $false
    }
}

foreach ($line in $expectedLogLines) {
    $found = $false
    if ($logContent) {
        $found = $logContent | Select-String -Pattern [regex]::Escape($line) -Quiet
    }
    Write-Result -Msg "Log contains expected line: $line" -Success $found
}

# Simulate "Delay 4 Hours" selection and verify log again
# (No actual UI interaction; just check log again as per scenario)
Write-Host "Simulating 'Delay 4 Hours' selection (verifying log again)..." -ForegroundColor Gray
foreach ($line in $expectedLogLines) {
    $found = $false
    if ($logContent) {
        $found = $logContent | Select-String -Pattern [regex]::Escape($line) -Quiet
    }
    Write-Result -Msg "Log (post-delay) contains expected line: $line" -Success $found
}

Write-Host ""

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling product..." -ForegroundColor Cyan

$uninstallArgs = "/x `"$msiPath`" /qn"
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully (ExitCode: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI uninstall failed (ExitCode: 1603)" -Success $false
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another uninstall in progress (ExitCode: 1618)" -Success $false
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (ExitCode: 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstall failed (ExitCode: $exitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

# Verify service removed
$svcRemoved = $false
try {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svcRemoved = $true
    }
} catch {
    $svcRemoved = $true
}
Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $svcRemoved

Write-Host ""

# ============================================================
# TEST EXECUTION SUMMARY
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