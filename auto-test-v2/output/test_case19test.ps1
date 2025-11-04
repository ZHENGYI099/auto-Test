# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$test_case_id = "case19test"
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

# Define MSI path and product name
$msiPath = "C:\VMShare\cmdextension.msi"
$msiProductCode = $null
$serviceName = "CloudManagedDesktopExtension"
$logFilePath = "C:\ProgramData\Microsoft\CMDExtension\Logs\AppHealthPlugin.log"

# List of target programs and their display names
$targetPrograms = @(
    @{ Name = "Teams Machine-Wide Installer"; LogKey = "TeamsAppVersion" },
    @{ Name = "Remote Desktop WebRTC Redirector Service"; LogKey = "WebRTCRedirectorVersion" },
    @{ Name = "MsMmrHostMsi"; LogKey = "MMRVersion" }, # Used as fallback for MMRVersion
    @{ Name = "Remote Desktop Multimedia Redirection Service"; LogKey = "MMRVersion" },
    @{ Name = "Microsoft Teams"; LogKey = "TeamsAppV2Version" },
    @{ Name = "Microsoft Teams classic"; LogKey = "TeamsAppV2Version" }
)

# Helper: Get installed product version by display name
function Get-InstalledProgramVersion {
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

# Helper: Get MSI product code from MSI file
function Get-MSIProductCode {
    param([string]$msiPath)
    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $windowsInstaller, @($msiPath, 0))
        $view = $database.GetType().InvokeMember("OpenView", 'InvokeMethod', $null, $database, @("SELECT Value FROM Property WHERE Property = 'ProductCode'"))
        $view.GetType().InvokeMember("Execute", 'InvokeMethod', $null, $view, $null)
        $record = $view.GetType().InvokeMember("Fetch", 'InvokeMethod', $null, $view, $null)
        $productCode = $record.GetType().InvokeMember("StringData", 'GetProperty', $null, $record, 1)
        return $productCode
    } catch {
        return $null
    }
}

# Check if product already installed
$msiProductCode = Get-MSIProductCode -msiPath $msiPath
$alreadyInstalled = $false
if ($msiProductCode) {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $msiProductCode }
    if ($installed) {
        $alreadyInstalled = $true
        Write-Result -Msg "Product already installed: $($installed.Name) $($installed.Version)" -Success $true
    }
}

if ($alreadyInstalled) {
    Write-Host "Uninstalling existing product before test..." -ForegroundColor Yellow
    $uninstallCmd = "msiexec.exe /x $msiProductCode /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $msiProductCode /qn" -Wait -PassThru
    if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
        Write-Result -Msg "Previous installation removed" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous installation (ExitCode: $($uninstallProc.ExitCode))" -Success $false
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
    $installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $installProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Result -Msg "MSI installed successfully (ExitCode: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "Installation failed (ExitCode: 1603)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (ExitCode: 1618)" -Success $false
        Stop-Transcript
        exit 1
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (ExitCode: 1925)" -Success $false
        Stop-Transcript
        exit 1
    } else {
        Write-Result -Msg "Unexpected MSI exit code: $exitCode" -Success $false
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Result -Msg "Exception during MSI install: $_" -Success $false
    Stop-Transcript
    exit 1
}

# Wait for service to start (if applicable)
Start-Sleep -Seconds 10
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -eq "Running") {
        Write-Result -Msg "Service '$serviceName' is running after install" -Success $true
    } else {
        Write-Result -Msg "Service '$serviceName' is not running (Status: $($svc.Status))" -Success $false
    }
} catch {
    Write-Result -Msg "Service '$serviceName' not found after install" -Success $false
}

Write-Host ""
# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying App Health Plugin log..." -ForegroundColor Cyan

# Wait for 2 minutes as per scenario
Start-Sleep -Seconds 120

if (Test-Path $logFilePath) {
    Write-Result -Msg "Log file exists: $logFilePath" -Success $true
    $logContent = Get-Content $logFilePath -Raw
} else {
    Write-Result -Msg "Log file not found: $logFilePath" -Success $false
    $logContent = ""
}

# Step 2: Get installed program versions
$programVersions = @{}
foreach ($prog in $targetPrograms) {
    $ver = Get-InstalledProgramVersion -displayName $prog.Name
    $programVersions[$prog.Name] = $ver
}

# Step 3: Validate log values against installed program versions

# TeamsAppVersion
$teamsInstallerVer = $programVersions["Teams Machine-Wide Installer"]
if ($teamsInstallerVer) {
    $expectedTeamsAppVersion = $teamsInstallerVer
} else {
    $expectedTeamsAppVersion = "NoCurrentVersionFound"
}
$actualTeamsAppVersion = ($logContent | Select-String -Pattern "TeamsAppVersion\s*:\s*(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }) | Select-Object -First 1
if ($actualTeamsAppVersion) {
    if ($actualTeamsAppVersion -eq $expectedTeamsAppVersion) {
        Write-Result -Msg "TeamsAppVersion matches expected ($expectedTeamsAppVersion)" -Success $true
    } else {
        Write-Result -Msg "TeamsAppVersion mismatch: expected '$expectedTeamsAppVersion', found '$actualTeamsAppVersion'" -Success $false
    }
} else {
    Write-Result -Msg "TeamsAppVersion not found in log" -Success $false
}

# WebRTCRedirectorVersion
$webrtcVer = $programVersions["Remote Desktop WebRTC Redirector Service"]
if ($webrtcVer) {
    $expectedWebRTCRedirectorVersion = $webrtcVer
} else {
    $expectedWebRTCRedirectorVersion = "NoCurrentVersionFound"
}
$actualWebRTCRedirectorVersion = ($logContent | Select-String -Pattern "WebRTCRedirectorVersion\s*:\s*(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }) | Select-Object -First 1
if ($actualWebRTCRedirectorVersion) {
    if ($actualWebRTCRedirectorVersion -eq $expectedWebRTCRedirectorVersion) {
        Write-Result -Msg "WebRTCRedirectorVersion matches expected ($expectedWebRTCRedirectorVersion)" -Success $true
    } else {
        Write-Result -Msg "WebRTCRedirectorVersion mismatch: expected '$expectedWebRTCRedirectorVersion', found '$actualWebRTCRedirectorVersion'" -Success $false
    }
} else {
    Write-Result -Msg "WebRTCRedirectorVersion not found in log" -Success $false
}

# MMRVersion
$mmrVer = $programVersions["Remote Desktop Multimedia Redirection Service"]
if ($mmrVer) {
    $expectedMMRVersion = $mmrVer
} else {
    $msmmrVer = $programVersions["MsMmrHostMsi"]
    if ($msmmrVer) {
        $expectedMMRVersion = $msmmrVer
    } else {
        $expectedMMRVersion = "NoCurrentVersionFound"
    }
}
$actualMMRVersion = ($logContent | Select-String -Pattern "MMRVersion\s*:\s*(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }) | Select-Object -First 1
if ($actualMMRVersion) {
    if ($actualMMRVersion -eq $expectedMMRVersion) {
        Write-Result -Msg "MMRVersion matches expected ($expectedMMRVersion)" -Success $true
    } else {
        Write-Result -Msg "MMRVersion mismatch: expected '$expectedMMRVersion', found '$actualMMRVersion'" -Success $false
    }
} else {
    Write-Result -Msg "MMRVersion not found in log" -Success $false
}

# TeamsAppV2Version
$teamsV2Ver = $programVersions["Microsoft Teams"]
if (-not $teamsV2Ver) {
    $teamsV2Ver = $programVersions["Microsoft Teams classic"]
}
if ($teamsV2Ver) {
    $expectedTeamsAppV2Version = $teamsV2Ver
} else {
    $expectedTeamsAppV2Version = "NoCurrentVersionFound"
}
$actualTeamsAppV2Version = ($logContent | Select-String -Pattern "TeamsAppV2Version\s*:\s*(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }) | Select-Object -First 1
if ($actualTeamsAppV2Version) {
    if ($actualTeamsAppV2Version -eq $expectedTeamsAppV2Version) {
        Write-Result -Msg "TeamsAppV2Version matches expected ($expectedTeamsAppV2Version)" -Success $true
    } else {
        Write-Result -Msg "TeamsAppV2Version mismatch: expected '$expectedTeamsAppV2Version', found '$actualTeamsAppV2Version'" -Success $false
    }
} else {
    Write-Result -Msg "TeamsAppV2Version not found in log" -Success $false
}

Write-Host ""
# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up: Uninstalling client agent..." -ForegroundColor Cyan

try {
    $uninstallArgs = "/x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
    $exitCode = $uninstallProc.ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 1605) {
        Write-Result -Msg "MSI uninstalled successfully (ExitCode: $exitCode)" -Success $true
    } elseif ($exitCode -eq 1603) {
        Write-Result -Msg "Uninstallation failed (ExitCode: 1603)" -Success $false
    } elseif ($exitCode -eq 1618) {
        Write-Result -Msg "Another installation in progress (ExitCode: 1618)" -Success $false
    } elseif ($exitCode -eq 1925) {
        Write-Result -Msg "Insufficient privileges (ExitCode: 1925)" -Success $false
    } else {
        Write-Result -Msg "Unexpected MSI uninstall exit code: $exitCode" -Success $false
    }
} catch {
    Write-Result -Msg "Exception during MSI uninstall: $_" -Success $false
}

# Verify service removed
Start-Sleep -Seconds 5
try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Result -Msg "Service '$serviceName' still present after uninstall" -Success $false
} catch {
    Write-Result -Msg "Service '$serviceName' removed after uninstall" -Success $true
}

Write-Host ""
# ============================================================
# TEST SUMMARY
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Passed: $script:SuccessCount" -ForegroundColor Green
Write-Host "Total Failed: $script:FailCount" -ForegroundColor Red
if ($script:FailCount -eq 0) {
    Write-Host "[PASS] All checks passed for test case: $test_case_id" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Some checks failed for test case: $test_case_id" -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan

Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')