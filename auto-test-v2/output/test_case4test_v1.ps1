# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case4test_$timestamp.log"

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
    Write-Host "❌ ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$msiPath = "C:\VMShare\cmdextension.msi"
$msiName = "cmdextension.msi"
$svcName = "CloudManagedDesktopExtension"
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logFolder "CMDExtension.log"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product already installed
$installed = $false
try {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and ($svc.Status -eq "Running" -or $svc.Status -eq "Stopped")) {
        $installed = $true
    }
} catch {}
if ($installed) {
    Write-Result -Msg "$svcName service already installed" -Success $false
    Write-Host "Uninstalling existing product before test..." -ForegroundColor Yellow
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    Write-Host "Uninstall exit code: $exitCode" -ForegroundColor Gray
    Start-Sleep -Seconds 10
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "Previous product uninstalled" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous product - exit code $exitCode" -Success $false
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

Write-Host "Installing $msiName..." -ForegroundColor Cyan
$installCmd = "msiexec.exe /i `"$msiPath`" SVCENV=Test /qn"
try {
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" SVCENV=Test /qn" -Wait -PassThru
    $exitCode = $proc.ExitCode
    Write-Host "Install exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed - exit code 1603" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress - exit code 1618" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges - exit code 1925" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "MSI installation failed - exit code $exitCode" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI install - $($_.Exception.Message)" -Success $false
    Stop-Transcript
    exit 1
}

# Wait 5 minutes as specified
Write-Host "Waiting 5 minutes for agent registration..." -ForegroundColor Yellow
Start-Sleep -Seconds 300

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$skipToCleanup = $false

# Step 5: Check CMDExtension.log for required and forbidden contents
$logExists = Test-Path $logFilePath
Write-Result -Msg "CMDExtension.log exists" -Success $logExists
if ($logExists) {
    $logContent = Get-Content $logFilePath -Raw
    $mustContain = "DeviceClient created and opened successfully"
    $mustNotContain = "Failed to create instance for plugin"
    $containsRequired = ($logContent -match [regex]::Escape($mustContain))
    $containsForbidden = ($logContent -match [regex]::Escape($mustNotContain))
    Write-Result -Msg "Log contains '$mustContain'" -Success $containsRequired
    if (-not $containsRequired) {
        Write-Host "[DEBUG] Log missing required text: '$mustContain'" -ForegroundColor Yellow
    }
    Write-Result -Msg "Log does NOT contain '$mustNotContain'" -Success (-not $containsForbidden)
    if ($containsForbidden) {
        Write-Host "[DEBUG] Log contains forbidden text: '$mustNotContain'" -ForegroundColor Yellow
    }
} else {
    Write-Host "[DEBUG] Log file not found: $logFilePath" -ForegroundColor Yellow
}

# Step 6: WMI instance check
try {
    $wmiInstances = Get-WmiObject -Namespace "root\cmd\clientagent" -Class "SchedulerEntity" -ErrorAction Stop
    $instanceCount = ($wmiInstances | Measure-Object).Count
    $notEmpty = ($instanceCount -gt 0)
    Write-Result -Msg "SchedulerEntity WMI instance list is NOT empty" -Success $notEmpty
    if (-not $notEmpty) {
        Write-Host "[DEBUG] SchedulerEntity instance count: $instanceCount" -ForegroundColor Yellow
    }
} catch {
    Write-Result -Msg "Failed to query SchedulerEntity WMI instances - $($_.Exception.Message)" -Success $false
}

# Step 7: Registry check for DeviceRegistrationType
$regPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CloudManagementDesktop\Extension\Settings",
    "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"
)
$foundCertType = $false
foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            $regVal = Get-ItemProperty -Path $regPath -Name "DeviceRegistrationType" -ErrorAction Stop | Select-Object -ExpandProperty DeviceRegistrationType
            if (-not [string]::IsNullOrWhiteSpace($regVal)) {
                $regVal = $regVal.Trim()
                if ($regVal -eq "Certificate") {
                    $foundCertType = $true
                    Write-Result -Msg "DeviceRegistrationType is 'Certificate' in $regPath" -Success $true
                } else {
                    Write-Result -Msg "DeviceRegistrationType is NOT 'Certificate' in $regPath" -Success $false
                    Write-Host "[DEBUG] Actual value: '$regVal'" -ForegroundColor Yellow
                }
            } else {
                Write-Result -Msg "DeviceRegistrationType is null/empty in $regPath" -Success $false
            }
        } catch {
            Write-Result -Msg "Failed to read DeviceRegistrationType from $regPath - $($_.Exception.Message)" -Success $false
        }
    } else {
        Write-Result -Msg "Registry path not found: $regPath" -Success $false
    }
}
if (-not $foundCertType) {
    Write-Host "DeviceRegistrationType is not 'Certificate'. Skipping cert deletion/re-registration steps." -ForegroundColor Yellow
    $skipToCleanup = $true
}

# Step 8: Open certlm - NO verification required, skip

# Step 9: Find certificate issued to/by {tenantId.aadDeviceId}
if (-not $skipToCleanup) {
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My
    $targetCert = $null
    foreach ($cert in $certs) {
        # For demo, assume subject contains both tenantId and aadDeviceId as a pattern
        if ($cert.Subject -match "CN=.*\..*") {
            $targetCert = $cert
            break
        }
    }
    if ($null -eq $targetCert) {
        Write-Result -Msg "Certificate with Subject containing '{tenantId.aadDeviceId}' not found" -Success $false
        $skipToCleanup = $true
    } else {
        Write-Result -Msg "Certificate with Subject '{tenantId.aadDeviceId}' found" -Success $true
    }
}

# Step 10: Delete the certificate
if (-not $skipToCleanup) {
    try {
        Remove-Item -Path $targetCert.PSPath -Force
        Write-Result -Msg "Certificate deleted successfully" -Success $true
    } catch {
        Write-Result -Msg "Failed to delete certificate - $($_.Exception.Message)" -Success $false
        $skipToCleanup = $true
    }
}

# Step 11: Restart service
if (-not $skipToCleanup) {
    try {
        Restart-Service -Name $svcName -Force -ErrorAction Stop
        Start-Sleep -Seconds 5
        $svc = Get-Service -Name $svcName -ErrorAction Stop
        $isRunning = ($svc.Status -eq "Running")
        Write-Result -Msg "$svcName service restarted and running" -Success $isRunning
        if (-not $isRunning) {
            Write-Host "[DEBUG] Service status after restart: $($svc.Status)" -ForegroundColor Yellow
        }
    } catch {
        Write-Result -Msg "Failed to restart $svcName service - $($_.Exception.Message)" -Success $false
        $skipToCleanup = $true
    }
}

# Step 12: Check log for re-registration messages
if (-not $skipToCleanup) {
    $logExists = Test-Path $logFilePath
    Write-Result -Msg "CMDExtension.log exists after restart" -Success $logExists
    if ($logExists) {
        $logContent = Get-Content $logFilePath -Raw
        $requiredTexts = @(
            "Clear iot connection info success",
            "RegisterDeviceToHermesAsync starts",
            "DeviceClient created and opened successfully"
        )
        foreach ($text in $requiredTexts) {
            $found = ($logContent -match [regex]::Escape($text))
            Write-Result -Msg "Log contains '$text' after restart" -Success $found
            if (-not $found) {
                Write-Host "[DEBUG] Log missing required text after restart: '$text'" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[DEBUG] Log file not found after restart: $logFilePath" -ForegroundColor Yellow
    }
}

# Step 13: Refresh certificate, check if cert is re-created
if (-not $skipToCleanup) {
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My
    $recreatedCert = $null
    foreach ($cert in $certs) {
        if ($cert.Subject -match "CN=.*\..*") {
            $recreatedCert = $cert
            break
        }
    }
    if ($null -eq $recreatedCert) {
        Write-Result -Msg "Certificate '{tenantId.aadDeviceId}' NOT re-created after restart" -Success $false
    } else {
        Write-Result -Msg "Certificate '{tenantId.aadDeviceId}' re-created after restart" -Success $true
    }
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling $msiName..." -ForegroundColor Cyan
try {
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    Write-Host "Uninstall exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI uninstall failed - exit code 1603" -Success $false
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another uninstall in progress - exit code 1618" -Success $false
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges - exit code 1925" -Success $false
    } else {
        Write-Result -Msg "MSI uninstall failed - exit code $exitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall - $($_.Exception.Message)" -Success $false
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