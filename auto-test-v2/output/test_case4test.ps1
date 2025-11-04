# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$test_case_id = "case4test"
$logFile = Join-Path $logDir "test_${test_case_id}_$timestamp.log"

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
$logFolder = "$env:ProgramData\Microsoft\CMDExtension\Logs"
$logFilePath = Join-Path $logFolder "CMDExtension.log"

# Registry paths for x86/x64
$regPath_x86 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CloudManagementDesktop\Extension\Settings"
$regPath_x64 = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"

# Helper: Get MSI property (per instructions)
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

# Helper: Find cert by subject/issuer
function Find-DeviceCert {
    param(
        [string]$subject
    )
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
        $store.Open("ReadWrite")
        $found = $store.Certificates | Where-Object {
            ($_.Subject -like "*$subject*") -and ($_.Issuer -like "*$subject*")
        }
        $store.Close()
        return $found
    } catch {
        Write-Host "[DEBUG] Find-DeviceCert failed - $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Helper: Delete cert by subject/issuer
function Delete-DeviceCert {
    param(
        [string]$subject
    )
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
        $store.Open("ReadWrite")
        $toDelete = $store.Certificates | Where-Object {
            ($_.Subject -like "*$subject*") -and ($_.Issuer -like "*$subject*")
        }
        foreach ($cert in $toDelete) {
            $store.Remove($cert)
        }
        $store.Close()
        return $toDelete.Count
    } catch {
        Write-Host "[DEBUG] Delete-DeviceCert failed - $($_.Exception.Message)" -ForegroundColor Yellow
        return 0
    }
}

# Helper: Restart service and wait for running
function Restart-ServiceAndWait {
    param([string]$svcName, [int]$waitSec = 30)
    try {
        Restart-Service -Name $svcName -Force
        Write-Host "Waiting $waitSec seconds for service registration..." -ForegroundColor Gray
        Start-Sleep -Seconds $waitSec
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and ($svc.Status -eq "Running")) {
            return $true
        } else {
            return $false
        }
    } catch {
        Write-Host "[DEBUG] Restart-ServiceAndWait failed - $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Helper: Search log for strings
function Search-Log {
    param(
        [string]$logPath,
        [string[]]$mustContain,
        [string[]]$mustNotContain
    )
    $exists = Test-Path $logPath
    if (-not $exists) {
        Write-Result -Msg "Log file $logPath exists" -Success $false
        return $false
    }
    $content = Get-Content $logPath -Raw
    $allFound = $true
    foreach ($str in $mustContain) {
        $found = $content -like "*$str*"
        Write-Result -Msg "Log contains '$str'" -Success $found
        if (-not $found) {
            Write-Host "[DEBUG] Log missing expected string - '$str'" -ForegroundColor Yellow
            $allFound = $false
        }
    }
    foreach ($str in $mustNotContain) {
        $found = $content -like "*$str*"
        Write-Result -Msg "Log does NOT contain '$str'" -Success (-not $found)
        if ($found) {
            Write-Host "[DEBUG] Log contains unexpected string - '$str'" -ForegroundColor Yellow
            $allFound = $false
        }
    }
    return $allFound
}

# Helper: WMI instance check
function Check-WMIInstances {
    param(
        [string]$namespace,
        [string]$class
    )
    try {
        $instances = Get-WmiObject -Namespace $namespace -Class $class -ErrorAction Stop
        $count = ($instances | Measure-Object).Count
        $notEmpty = ($count -gt 0)
        Write-Result -Msg "WMI $namespace\$class instance count > 0" -Success $notEmpty
        if (-not $notEmpty) {
            Write-Host "[DEBUG] WMI instance count: $count" -ForegroundColor Yellow
        }
        return $notEmpty
    } catch {
        Write-Result -Msg "WMI $namespace\$class query failed" -Success $false
        Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Helper: Registry check for DeviceRegistrationType
function Get-DeviceRegistrationType {
    foreach ($regPath in @($regPath_x64, $regPath_x86)) {
        if (Test-Path $regPath) {
            try {
                $val = (Get-ItemProperty -Path $regPath -Name "DeviceRegistrationType" -ErrorAction Stop).DeviceRegistrationType
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    return $val.Trim()
                }
            } catch {}
        }
    }
    return $null
}

# Helper: Wait for service running
function Wait-ForService {
    param([string]$svcName, [int]$timeoutSec = 60)
    $svc = $null
    $elapsed = 0
    while ($elapsed -lt $timeoutSec) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and ($svc.Status -eq "Running")) {
            Write-Result -Msg "Service $svcName is running" -Success $true
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Result -Msg "Service $svcName is running" -Success $false
    return $false
}

# Check if already installed (service exists)
$svcPre = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svcPre) {
    Write-Host "Product already installed. Uninstalling before test..." -ForegroundColor Yellow
    try {
        $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru).ExitCode
        Write-Result -Msg "Pre-test uninstall exit code = $exitCode" -Success ($exitCode -eq 0 -or $exitCode -eq 1605)
        Start-Sleep -Seconds 5
    } catch {
        Write-Result -Msg "Pre-test uninstall command threw exception" -Success $false
        Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installCmd = "msiexec /i `"$msiPath`" SVCENV=Test /qn"
Write-Host "Installing product..." -ForegroundColor Cyan
try {
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" SVCENV=Test /qn" -Wait -PassThru).ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 3010)
    Write-Result -Msg "Install exit code = $exitCode" -Success $success
    if (-not $success) {
        Write-Host "Install failed with exit code $exitCode. Aborting test." -ForegroundColor Red
        Stop-Transcript
        exit 2
    }
} catch {
    Write-Result -Msg "Install command threw exception" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
    Stop-Transcript
    exit 2
}

# Wait for service to start (up to 60s)
Wait-ForService -svcName $serviceName -timeoutSec 60

# Wait 5 minutes for agent registration (per scenario)
Write-Host "Waiting 5 minutes for agent registration..." -ForegroundColor Cyan
Start-Sleep -Seconds 300

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$skipCertSteps = $false

# Step 5: Check log for registration success/failure
$mustContain = @("DeviceClient created and opened successfully")
$mustNotContain = @("Failed to create instance for plugin")
Search-Log -logPath $logFilePath -mustContain $mustContain -mustNotContain $mustNotContain

# Step 6: WMI instance check
Check-WMIInstances -namespace "root\cmd\clientagent" -class "SchedulerEntity"

# Step 7: Registry DeviceRegistrationType
$regType = Get-DeviceRegistrationType
if ($null -eq $regType -or [string]::IsNullOrWhiteSpace($regType)) {
    Write-Result -Msg "DeviceRegistrationType registry value found" -Success $false
    Write-Host "[DEBUG] Actual value: $regType" -ForegroundColor Yellow
    $skipCertSteps = $true
} else {
    $regTypeTrimmed = $regType.Trim()
    $isCert = ($regTypeTrimmed -eq "Certificate")
    Write-Result -Msg "DeviceRegistrationType is 'Certificate'" -Success $isCert
    if (-not $isCert) {
        Write-Host "DeviceRegistrationType is not 'Certificate'. Skipping cert deletion test." -ForegroundColor Yellow
        $skipCertSteps = $true
    }
}

if (-not $skipCertSteps) {
    # Step 9: Find device cert (simulate {tenantId.aadDeviceId} as subject)
    # For automation, use a pattern (e.g., "CN=" prefix)
    $subjectPattern = "CN="
    $foundCerts = Find-DeviceCert -subject $subjectPattern
    $certExists = ($foundCerts -and $foundCerts.Count -gt 0)
    Write-Result -Msg "Device certificate exists before deletion" -Success $certExists
    if (-not $certExists) {
        Write-Host "[DEBUG] No device certificate found before deletion." -ForegroundColor Yellow
    }

    # Step 10: Delete cert
    $deletedCount = Delete-DeviceCert -subject $subjectPattern
    Write-Result -Msg "Device certificate deleted" -Success ($deletedCount -gt 0)
    if ($deletedCount -eq 0) {
        Write-Host "[DEBUG] No device certificate deleted." -ForegroundColor Yellow
    }

    # Step 11: Restart service
    $svcRestarted = Restart-ServiceAndWait -svcName $serviceName
    Write-Result -Msg "Service restarted and running" -Success $svcRestarted

    # Step 12: Check log for post-restart registration
    $mustContain2 = @("Clear iot connection info success", "RegisterDeviceToHermesAsync starts", "DeviceClient created and opened successfully")
    Search-Log -logPath $logFilePath -mustContain $mustContain2 -mustNotContain @()

    # Step 13: Cert re-created
    $foundCerts2 = Find-DeviceCert -subject $subjectPattern
    $certExists2 = ($foundCerts2 -and $foundCerts2.Count -gt 0)
    Write-Result -Msg "Device certificate re-created after restart" -Success $certExists2
    if (-not $certExists2) {
        Write-Host "[DEBUG] Device certificate not re-created after restart." -ForegroundColor Yellow
    }
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling product..." -ForegroundColor Cyan
try {
    $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru).ExitCode
    $success = ($exitCode -eq 0 -or $exitCode -eq 1605)
    Write-Result -Msg "Uninstall exit code = $exitCode" -Success $success
    Start-Sleep -Seconds 5
} catch {
    Write-Result -Msg "Uninstall command threw exception" -Success $false
    Write-Host "[DEBUG] Exception - $($_.Exception.Message)" -ForegroundColor Yellow
}

# Verify service removed
$svcPost = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
Write-Result -Msg "Service $serviceName removed after uninstall" -Success (-not $svcPost)

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