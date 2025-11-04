# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case21test_$timestamp.log"

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

# Helper function to get MSI property (per instructions)
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
    Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Define MSI path and product/service names
$msiPath = "C:\VMShare\cmdextension.msi"
$installFolder = "C:\Program Files\Microsoft Cloud Managed Desktop Extension\CMDExtension"
$serviceName = "CloudManagedDesktopExtension"
$productName = "Microsoft Cloud Managed Desktop Extension"

# Check if MSI exists
if (-not (Test-Path $msiPath)) {
    Write-Result -Msg "MSI file not found at $msiPath" -Success $false
    Stop-Transcript
    exit 2
} else {
    Write-Result -Msg "MSI file found at $msiPath" -Success $true
}

# Check if product is already installed (by service existence)
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Result -Msg "Service '$serviceName' already installed. Attempting uninstall for clean state." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    Write-Host "Uninstall exit code: $uninstallExitCode" -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $serviceExists) {
        Write-Result -Msg "Previous installation removed successfully." -Success $true
    } else {
        Write-Result -Msg "Failed to remove previous installation. Aborting." -Success $false
        Stop-Transcript
        exit 3
    }
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$installCmd = "msiexec.exe /i `"$msiPath`" /qn"
Write-Host "Installing MSI silently..." -ForegroundColor Cyan
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
    $exitCode = $installProcess.ExitCode
    Write-Host "MSI install exit code: $exitCode" -ForegroundColor Gray
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (exit code: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "MSI installation failed (exit code: 1603)" -Success $false
        Stop-Transcript
        exit 4
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (exit code: 1618)" -Success $false
        Stop-Transcript
        exit 5
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
        Stop-Transcript
        exit 6
    } else {
        Write-Result -Msg "MSI installation failed (exit code: $exitCode)" -Success $false
        Stop-Transcript
        exit 7
    }
} catch {
    Write-Result -Msg "Exception during MSI installation: $_" -Success $false
    Stop-Transcript
    exit 8
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 5
$serviceObj = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceObj -and $serviceObj.Status -eq 'Running') {
    Write-Result -Msg "Service '$serviceName' is running after installation." -Success $true
} elseif ($serviceObj) {
    Write-Result -Msg "Service '$serviceName' installed but not running (status: $($serviceObj.Status))." -Success $false
} else {
    Write-Result -Msg "Service '$serviceName' not found after installation." -Success $false
}

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 2: Check install folder exists
if (Test-Path $installFolder) {
    Write-Result -Msg "Install folder exists: $installFolder" -Success $true
} else {
    Write-Result -Msg "Install folder missing: $installFolder" -Success $false
    Stop-Transcript
    exit 9
}

# Step 3: Get VersionInfo of all Microsoft.Management.Services.* files (excluding .config and .pdb)
$files = Get-ChildItem -Path $installFolder -Recurse -Filter "Microsoft.Management.Services.*" | Where-Object {
    ($_.Extension -ne ".config") -and ($_.Extension -ne ".pdb")
}

if ($files.Count -eq 0) {
    Write-Result -Msg "No Microsoft.Management.Services.* files found in $installFolder" -Success $false
    Stop-Transcript
    exit 10
} else {
    Write-Result -Msg "Found $($files.Count) Microsoft.Management.Services.* files for version check." -Success $true
}

# Step 4: Check FileVersion matches MSI ProductVersion
$msiVersion = Get-MSIProperty -msiPath $msiPath -property "ProductVersion"
if ([string]::IsNullOrWhiteSpace($msiVersion)) {
    Write-Result -Msg "Could not retrieve MSI ProductVersion" -Success $false
    Stop-Transcript
    exit 11
}
Write-Result -Msg "MSI ProductVersion: $msiVersion" -Success $true

foreach ($file in $files) {
    $fileVersion = $file.VersionInfo.FileVersion
    if ([string]::IsNullOrWhiteSpace($fileVersion)) {
        Write-Result -Msg "File $($file.Name) has no version info" -Success $false
        continue
    }
    $fileVersion = $fileVersion.Trim()
    if ($fileVersion -eq $msiVersion) {
        Write-Result -Msg "Version matches for $($file.Name): $fileVersion" -Success $true
    } else {
        Write-Result -Msg "Version mismatch for $($file.Name): $fileVersion (expected: $msiVersion)" -Success $false
    }
}

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Uninstalling MSI silently..." -ForegroundColor Cyan
try {
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    $uninstallExitCode = $uninstallProcess.ExitCode
    Write-Host "MSI uninstall exit code: $uninstallExitCode" -ForegroundColor Gray
    if ($uninstallExitCode -eq 0 -or $uninstallExitCode -eq 3010) {
        Write-Result -Msg "MSI uninstalled successfully (exit code: $uninstallExitCode)" -Success $true
    } elseif ($uninstallExitCode -eq 1605) {
        Write-Result -Msg "Product not installed (exit code: 1605)" -Success $true
    } elseif ($uninstallExitCode -eq 1603) {
        Write-Result -Msg "MSI uninstall failed (exit code: 1603)" -Success $false
    } elseif ($uninstallExitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (exit code: 1618)" -Success $false
    } elseif ($uninstallExitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (exit code: 1925)" -Success $false
    } else {
        Write-Result -Msg "MSI uninstall failed (exit code: $uninstallExitCode)" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

Start-Sleep -Seconds 5

# Verify service removed
$serviceObj = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $serviceObj) {
    Write-Result -Msg "Service '$serviceName' removed after uninstall." -Success $true
} else {
    Write-Result -Msg "Service '$serviceName' still present after uninstall." -Success $false
}

# Verify install folder removed
if (-not (Test-Path $installFolder)) {
    Write-Result -Msg "Install folder removed: $installFolder" -Success $true
} else {
    Write-Result -Msg "Install folder still present after uninstall: $installFolder" -Success $false
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red

if ($script:FailCount -eq 0) {
    Write-Host "TEST RESULT: SUCCESS" -ForegroundColor Green
} else {
    Write-Host "TEST RESULT: FAILED" -ForegroundColor Red
}

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')