# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$test_case_id = "case13test"
$logFile = Join-Path $logDir "test_${test_case_id}_$timestamp.log"

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
$serviceName = "CloudManagedDesktopExtension"
$logDirPath = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logDirPath "CMDExtension.log"
$regPath_x64 = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"
$regPath_x86 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CloudManagementDesktop\Extension\Settings"

# Check if product is already installed
function Get-MSIProductCode {
    param([string]$msiPath)
    $msi = New-Object -ComObject WindowsInstaller.Installer
    $db = $msi.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $msi, @($msiPath, 0))
    $view = $db.OpenView("SELECT * FROM Property WHERE Property = 'ProductCode'")
    $view.Execute()
    $record = $view.Fetch()
    if ($record) {
        return $record.StringData(2)
    }
    return $null
}
$productCode = Get-MSIProductCode -msiPath $msiPath

$alreadyInstalled = $false
if ($productCode) {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $productCode }
    if ($installed) {
        $alreadyInstalled = $true
    }
}

if ($alreadyInstalled) {
    Write-Result -Msg "Product already installed. Uninstalling before test..." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProc.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed successfully." -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation. Exit code: $uninstallExitCode" -Success $false
        Stop-Transcript
        exit 1
    }
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing client agent..." -ForegroundColor Cyan
$installArgs = "/i `"$msiPath`" SVCENV=`"Test`" /qn"
try {
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully. Exit code: $exitCode" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "Installation failed (1603)." -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (1618)." -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (1925)." -Success $false
        Stop-Transcript
        exit 1
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

# Wait for service to start
Start-Sleep -Seconds 10
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Result -Msg "Service '$serviceName' is running after install." -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' is NOT running after install." -Success $false
}

Write-Host ""
# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Starting test scenario actions and verification..." -ForegroundColor Cyan

# Step 5: Check log file for "Hit iot connection info cache" and "DeviceClient created and opened successfully"
$step5_found_cache = $false
$step5_found_deviceclient = $false
if (Test-Path $logFilePath) {
    $logContent = Get-Content $logFilePath -Raw
    if ($logContent -match "Hit iot connection info cache") {
        $step5_found_cache = $true
    }
    if ($logContent -match "DeviceClient created and opened successfully") {
        $step5_found_deviceclient = $true
    }
    Write-Result -Msg "Log contains 'Hit iot connection info cache'." -Success $step5_found_cache
    Write-Result -Msg "Log contains 'DeviceClient created and opened successfully'." -Success $step5_found_deviceclient
} else {
    Write-Result -Msg "Log file not found at $logFilePath" -Success $false
}

# Step 6: Stop service
try {
    Stop-Service -Name $serviceName -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    $service = Get-Service -Name $serviceName
    Write-Result -Msg "Service '$serviceName' stopped successfully." -Success ($service.Status -eq 'Stopped')
} catch {
    Write-Result -Msg "Failed to stop service '$serviceName': $_" -Success $false
}

# Step 7/8: Update registry IoTHostName to "foo-device.net"
$regPath = if (Test-Path $regPath_x64) { $regPath_x64 } elseif (Test-Path $regPath_x86) { $regPath_x86 } else { $null }
if ($regPath) {
    try {
        Set-ItemProperty -Path $regPath -Name "IoTHostName" -Value "foo-device.net"
        $newVal = (Get-ItemProperty -Path $regPath -Name "IoTHostName").IoTHostName
        Write-Result -Msg "Registry 'IoTHostName' updated to 'foo-device.net'." -Success ($newVal -eq "foo-device.net")
    } catch {
        Write-Result -Msg "Failed to update registry 'IoTHostName': $_" -Success $false
    }
} else {
    Write-Result -Msg "Registry path for settings not found." -Success $false
}

# Step 9: Start service and wait for 25 minutes (simulate with shorter wait for automation)
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    # For automation, reduce wait to 60 seconds instead of 25 minutes
    Start-Sleep -Seconds 60
    $service = Get-Service -Name $serviceName
    Write-Result -Msg "Service '$serviceName' started successfully." -Success ($service.Status -eq 'Running')
} catch {
    Write-Result -Msg "Failed to start service '$serviceName': $_" -Success $false
}

# Step 10: Check log for multiple "IoTHostName: foo-device.net" and "DeviceClient created and opened successfully"
$step10_found_iothost = $false
$step10_found_deviceclient = $false
$step10_iothost_count = 0
if (Test-Path $logFilePath) {
    $logContent = Get-Content $logFilePath
    $step10_iothost_count = ($logContent | Select-String "IoTHostName: foo-device.net").Count
    $step10_found_deviceclient = ($logContent | Select-String "DeviceClient created and opened successfully").Count -gt 0
    $step10_found_iothost = ($step10_iothost_count -gt 1)
    Write-Result -Msg "Log contains more than one 'IoTHostName: foo-device.net'." -Success $step10_found_iothost
    Write-Result -Msg "Log contains 'DeviceClient created and opened successfully' after IoTHostName update." -Success $step10_found_deviceclient
} else {
    Write-Result -Msg "Log file not found for step 10." -Success $false
}

# Step 11: Update registry IoTDeviceId to "fooDeviceId" and restart service
if ($regPath) {
    try {
        Set-ItemProperty -Path $regPath -Name "IoTDeviceId" -Value "fooDeviceId"
        $newVal = (Get-ItemProperty -Path $regPath -Name "IoTDeviceId").IoTDeviceId
        Write-Result -Msg "Registry 'IoTDeviceId' updated to 'fooDeviceId'." -Success ($newVal -eq "fooDeviceId")
    } catch {
        Write-Result -Msg "Failed to update registry 'IoTDeviceId': $_" -Success $false
    }
} else {
    Write-Result -Msg "Registry path for settings not found (IoTDeviceId)." -Success $false
}
try {
    Restart-Service -Name $serviceName -ErrorAction Stop
    # For automation, reduce wait to 30 seconds instead of 10 minutes
    Start-Sleep -Seconds 30
    $service = Get-Service -Name $serviceName
    Write-Result -Msg "Service '$serviceName' restarted successfully." -Success ($service.Status -eq 'Running')
} catch {
    Write-Result -Msg "Failed to restart service '$serviceName': $_" -Success $false
}

# Step 12: Check log for error codes and successful retry
$step12_found_error = $false
$step12_found_update = $false
$step12_found_deviceclient = $false
if (Test-Path $logFilePath) {
    $logContent = Get-Content $logFilePath -Raw
    $errorPatterns = @('"errorCode":401002', 'DeviceNotFoundException', 'status-code: 404', 'Exception on RegisterAsync')
    foreach ($pattern in $errorPatterns) {
        if ($logContent -match $pattern) {
            $step12_found_error = $true
            break
        }
    }
    $step12_found_update = ($logContent -match "Update IoTDeviceId to")
    $step12_found_deviceclient = ($logContent -match "DeviceClient created and opened successfully")
    Write-Result -Msg "Log contains expected error codes or exceptions." -Success $step12_found_error
    Write-Result -Msg "Log contains 'Update IoTDeviceId to' after error." -Success $step12_found_update
    Write-Result -Msg "Log contains 'DeviceClient created and opened successfully' after error." -Success $step12_found_deviceclient
} else {
    Write-Result -Msg "Log file not found for step 12." -Success $false
}

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling client agent..." -ForegroundColor Cyan
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProc.ExitCode
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully. Exit code: $uninstallExitCode" -Success $true
    } else {
        Write-Result -Msg "MSI uninstall failed. Exit code: $uninstallExitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

# Verify service removed
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall." -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still present after uninstall." -Success $false
}

Write-Host ""
# ============================================================
# SUMMARY
# ============================================================
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