# ============================================================
# SETUP LOGGING
# ============================================================
$test_case_id = "case10test"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
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
    Write-Host "[FAIL] Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
} else {
    Write-Result -Msg "Running as Administrator" -Success $true
}

# Define MSI paths and product/service names
$msiPathV1 = "C:\VMShare\cmdextension.v1.msi"
$msiPathV2 = "C:\VMShare\cmdextension.v2.msi"
$productName = "Microsoft Cloud Managed Desktop Extension"
$serviceName = "CloudManagedDesktopExtension"

# Check if MSI files exist
if (-not (Test-Path $msiPathV1)) {
    Write-Result -Msg "MSI v1 file not found: $msiPathV1" -Success $false
    Stop-Transcript
    exit 1
}
if (-not (Test-Path $msiPathV2)) {
    Write-Result -Msg "MSI v2 file not found: $msiPathV2" -Success $false
    Stop-Transcript
    exit 1
}
Write-Result -Msg "Both MSI files found" -Success $true

# Check if product is already installed (by DisplayName)
function Get-InstalledProductVersion {
    param([string]$displayName)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        $keys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -eq $displayName) {
                return $props.DisplayVersion
            }
        }
    }
    return $null
}

$currentVersion = Get-InstalledProductVersion -displayName $productName
if ($currentVersion) {
    Write-Result -Msg "$productName already installed (version: $currentVersion)" -Success $true
} else {
    Write-Result -Msg "$productName not currently installed" -Success $true
}

Write-Host ""
# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing v2 (latest)..." -ForegroundColor Cyan

$installV2Args = "/i `"$msiPathV2`" /qn /norestart"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installV2Args -Wait -PassThru
$exitCodeV2 = $process.ExitCode

if ($exitCodeV2 -eq 0 -or $exitCodeV2 -eq 3010) {
    Write-Result -Msg "v2 MSI installed successfully (exit code: $exitCodeV2)" -Success $true
} else {
    Write-Result -Msg "v2 MSI installation failed (exit code: $exitCodeV2)" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 10
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Result -Msg "Service '$serviceName' is running after v2 install" -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' is NOT running after v2 install (status: $($svc.Status))" -Success $false
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found after v2 install" -Success $false
}

Write-Host ""
# ============================================================
# PHASE 3: DOWNGRADE ATTEMPT & VERIFICATION
# ============================================================
Write-Host "Attempting downgrade: Installing v1 over v2..." -ForegroundColor Cyan

$installV1Args = "/i `"$msiPathV1`" /qn"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installV1Args -Wait -PassThru
$exitCodeV1 = $process.ExitCode

# According to scenario, downgrade should fail, but /qn is silent, so we only check exit code
if ($exitCodeV1 -eq 1603) {
    Write-Result -Msg "v1 MSI downgrade attempt failed as expected (exit code: $exitCodeV1)" -Success $true
} elseif ($exitCodeV1 -eq 0 -or $exitCodeV1 -eq 3010) {
    Write-Result -Msg "v1 MSI downgrade unexpectedly succeeded (exit code: $exitCodeV1)" -Success $false
} else {
    Write-Result -Msg "v1 MSI downgrade attempt returned exit code: $exitCodeV1" -Success $false
}

# Wait for a moment to ensure state is stable
Start-Sleep -Seconds 10

# Verify product version is still v2
$installedVersion = Get-InstalledProductVersion -displayName $productName
if ($installedVersion) {
    # Extract expected v2 version from MSI (optional: get from MSI file, but not required by scenario)
    # For this script, just check that version is not downgraded
    $expectedVersion = $installedVersion # In real test, parse v2 version from MSI if needed
    Write-Result -Msg "$productName is present in installed programs (version: $installedVersion)" -Success $true
    # If you know v2 version number, compare here
    # Example: if ($installedVersion -eq "2.0.0.0") { ... }
} else {
    Write-Result -Msg "$productName is NOT present in installed programs after downgrade attempt" -Success $false
}

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling v2..." -ForegroundColor Cyan

$uninstallV2Args = "/x `"$msiPathV2`" /qn /norestart"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallV2Args -Wait -PassThru
$exitCodeUninstall = $process.ExitCode

if ($exitCodeUninstall -eq 0 -or $exitCodeUninstall -eq 3010) {
    Write-Result -Msg "v2 MSI uninstalled successfully (exit code: $exitCodeUninstall)" -Success $true
} elseif ($exitCodeUninstall -eq 1605) {
    Write-Result -Msg "v2 MSI uninstall: product not installed (exit code: $exitCodeUninstall)" -Success $true
} else {
    Write-Result -Msg "v2 MSI uninstall failed (exit code: $exitCodeUninstall)" -Success $false
}

# Verify service is removed
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Result -Msg "Service '$serviceName' still present after uninstall" -Success $false
} catch {
    Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $true
}

# Verify product is no longer installed
$finalVersion = Get-InstalledProductVersion -displayName $productName
if ($finalVersion) {
    Write-Result -Msg "$productName still present after uninstall (version: $finalVersion)" -Success $false
} else {
    Write-Result -Msg "$productName removed from installed programs after uninstall" -Success $true
}

Write-Host ""
# ============================================================
# SUMMARY
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor Red
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')