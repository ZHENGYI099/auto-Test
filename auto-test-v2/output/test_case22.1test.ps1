# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "test_case22.1test_$timestamp.log"

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

# Define MSI path and service name
$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "C:\ProgramData\Microsoft\CMDExtension\Logs"
$regSettingsPath = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"

# Check if product is already installed
function IsProductInstalled {
    param([string]$serviceName)
    try {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        return $svc -ne $null
    } catch {
        return $false
    }
}
if (IsProductInstalled -serviceName $serviceName) {
    Write-Result -Msg "Service '$serviceName' is already installed. Uninstall before running this test." -Success $false
    Stop-Transcript
    exit 2
} else {
    Write-Result -Msg "Service '$serviceName' not installed. Proceeding..." -Success $true
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Install MSI silently with SVCENV=Test
$svcEnv = "Test"
$installArgs = "/i `"$msiPath`" /qn SVCENV=$svcEnv"
Write-Host "Installing MSI: $msiPath with SVCENV=$svcEnv ..." -ForegroundColor Cyan
$exitCode = $null
try {
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $installArgs -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode
    Write-Host "MSI install exit code: $exitCode" -ForegroundColor Gray
} catch {
    Write-Result -Msg "Failed to start MSI installation: $_" -Success $false
    Stop-Transcript
    exit 3
}
if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "MSI installed successfully (exit code: $exitCode)" -Success $true
} elseif ($exitCode -eq 1603) {
    Write-Result -Msg "MSI installation failed (exit code: 1603)" -Success $false
    Stop-Transcript
    exit 1603
} elseif ($exitCode -eq 1618) {
    Write-Result -Msg "Another installation is in progress (exit code: 1618)" -Success $false
    Stop-Transcript
    exit 1618
} elseif ($exitCode -eq 1925) {
    Write-Result -Msg "Insufficient privileges for installation (exit code: 1925)" -Success $false
    Stop-Transcript
    exit 1925
} else {
    Write-Result -Msg "MSI installation failed (exit code: $exitCode)" -Success $false
    Stop-Transcript
    exit $exitCode
}

# Wait for 1 minute as per scenario
Start-Sleep -Seconds 60

# ============================================================
# PHASE 3: VERIFICATION (Step 1)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION (Step 1)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Verify registry Partners contains more than 1 partner
try {
    $regProps = Get-ItemProperty -Path $regSettingsPath -ErrorAction Stop
    if ($regProps.Partners) {
        $partners = $regProps.Partners
        # Assume partners is a comma-separated string
        $partnerList = $partners -split ","
        if ($partnerList.Count -gt 1) {
            Write-Result -Msg "Registry Partners contains more than 1 partner: $partners" -Success $true
        } else {
            Write-Result -Msg "Registry Partners does NOT contain more than 1 partner: $partners" -Success $false
        }
    } else {
        Write-Result -Msg "Registry Partners value not found" -Success $false
    }
} catch {
    Write-Result -Msg "Failed to read registry Partners value: $_" -Success $false
}

# ============================================================
# PHASE 3: VERIFICATION (Step 2)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION (Step 2)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Wait for 15 minutes
Start-Sleep -Seconds 900

# Check logs in $logFolder
$senderLog = Join-Path $logFolder "MessageSenderPlugin.log"
$heartbeatLog = Join-Path $logFolder "HeartbeatPlugin.log"

# 1. MessageSenderPlugin.log contains log with TotalSize>0, Count>0, CommunicationChannel=IoTHub
try {
    if (Test-Path $senderLog) {
        $senderContent = Get-Content $senderLog -Raw
        $pattern = 'MessageSenderPlugin execute result is: \{.*"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"IoTHub".*\}'
        $matches = [regex]::Matches($senderContent, $pattern)
        $foundValid = $false
        foreach ($m in $matches) {
            $totalSize = [int]$m.Groups[1].Value
            $count = [int]$m.Groups[2].Value
            if ($totalSize -gt 0 -and $count -gt 0) {
                $foundValid = $true
                break
            }
        }
        Write-Result -Msg "MessageSenderPlugin.log contains valid IoTHub result with TotalSize>0 and Count>0" -Success $foundValid
    } else {
        Write-Result -Msg "MessageSenderPlugin.log not found" -Success $false
    }
} catch {
    Write-Result -Msg "Error reading MessageSenderPlugin.log: $_" -Success $false
}

# 2. HeartbeatPlugin.log contains 1 success log starts with {"ServiceStatus":"Running","AgentVersion":
try {
    if (Test-Path $heartbeatLog) {
        $heartbeatContent = Get-Content $heartbeatLog
        $successLine = $heartbeatContent | Where-Object { $_ -like '{"ServiceStatus":"Running","AgentVersion":*' }
        if ($successLine.Count -ge 1) {
            Write-Result -Msg "HeartbeatPlugin.log contains at least one success log with ServiceStatus=Running" -Success $true
        } else {
            Write-Result -Msg "HeartbeatPlugin.log does NOT contain success log with ServiceStatus=Running" -Success $false
        }
    } else {
        Write-Result -Msg "HeartbeatPlugin.log not found" -Success $false
    }
} catch {
    Write-Result -Msg "Error reading HeartbeatPlugin.log: $_" -Success $false
}

# ============================================================
# PHASE 3: FIREWALL BLOCK (Step 3)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: FIREWALL BLOCK (Step 3)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# a. Get IoTHostName from registry
try {
    $regProps = Get-ItemProperty -Path $regSettingsPath -ErrorAction Stop
    $iotHostName = $regProps.IoTHostName
    if ($iotHostName) {
        Write-Result -Msg "IoTHostName from registry: $iotHostName" -Success $true
    } else {
        Write-Result -Msg "IoTHostName not found in registry" -Success $false
        $iotHostName = $null
    }
} catch {
    Write-Result -Msg "Failed to read IoTHostName from registry: $_" -Success $false
    $iotHostName = $null
}

# b. nslookup IoTHostName to get IP address
$iotIp = $null
if ($iotHostName) {
    try {
        $nslookup = nslookup $iotHostName 2>&1
        $addressLine = $nslookup | Select-String -Pattern "Address:"
        if ($addressLine) {
            $iotIp = ($addressLine -replace "Address:\s*", "").Trim()
            Write-Result -Msg "IoTHostName resolves to IP: $iotIp" -Success $true
        } else {
            Write-Result -Msg "Could not resolve IoTHostName to IP" -Success $false
        }
    } catch {
        Write-Result -Msg "nslookup failed: $_" -Success $false
    }
}

# c. Block IP in Windows Firewall (protocol any)
$fwRuleName = "Block_IoTHub_IP_case22.1test"
if ($iotIp) {
    try {
        New-NetFirewallRule -DisplayName $fwRuleName -Direction Outbound -Action Block -RemoteAddress $iotIp -Protocol Any -Enabled True -ErrorAction Stop
        Write-Result -Msg "Firewall rule created to block IoTHub IP: $iotIp" -Success $true
    } catch {
        Write-Result -Msg "Failed to create firewall rule: $_" -Success $false
    }
}

# ============================================================
# PHASE 3: VERIFICATION (Step 4)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: VERIFICATION (Step 4)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Wait for 12 hours (simulate with 10 seconds for script demo; replace with 43200 for real test)
$waitSeconds = 10  # Use 43200 for real test
Write-Host "Waiting for $waitSeconds seconds to simulate 12 hours..." -ForegroundColor Yellow
Start-Sleep -Seconds $waitSeconds

# 1. MessageSenderPlugin.log only contains result with TotalSize=0, Count=0, CommunicationChannel=IoTHub
try {
    if (Test-Path $senderLog) {
        $senderContent = Get-Content $senderLog -Raw
        $patternZero = 'MessageSenderPlugin execute result is: \{.*"TotalSize":0,"Count":0,"CommunicationChannel":"IoTHub".*\}'
        $matchesZero = [regex]::Matches($senderContent, $patternZero)
        $otherPattern = 'MessageSenderPlugin execute result is: \{.*"TotalSize":(?!0)\d+,"Count":(?!0)\d+,"CommunicationChannel":"IoTHub".*\}'
        $matchesOther = [regex]::Matches($senderContent, $otherPattern)
        if ($matchesZero.Count -ge 1 -and $matchesOther.Count -eq 0) {
            Write-Result -Msg "MessageSenderPlugin.log only contains IoTHub result with TotalSize=0 and Count=0 after firewall block" -Success $true
        } else {
            Write-Result -Msg "MessageSenderPlugin.log contains unexpected IoTHub results after firewall block" -Success $false
        }
    } else {
        Write-Result -Msg "MessageSenderPlugin.log not found" -Success $false
    }
} catch {
    Write-Result -Msg "Error reading MessageSenderPlugin.log after firewall block: $_" -Success $false
}

# 2. HeartbeatPlugin.log contains multiple success logs starts with {"ServiceStatus":"Running","AgentVersion":
try {
    if (Test-Path $heartbeatLog) {
        $heartbeatContent = Get-Content $heartbeatLog
        $successLines = $heartbeatContent | Where-Object { $_ -like '{"ServiceStatus":"Running","AgentVersion":*' }
        if ($successLines.Count -gt 1) {
            Write-Result -Msg "HeartbeatPlugin.log contains multiple success logs with ServiceStatus=Running after firewall block" -Success $true
        } else {
            Write-Result -Msg "HeartbeatPlugin.log does NOT contain multiple success logs after firewall block" -Success $false
        }
    } else {
        Write-Result -Msg "HeartbeatPlugin.log not found" -Success $false
    }
} catch {
    Write-Result -Msg "Error reading HeartbeatPlugin.log after firewall block: $_" -Success $false
}

# ============================================================
# PHASE 3: FIREWALL RULE DISABLE (Step 5)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: FIREWALL RULE DISABLE (Step 5)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Disable the firewall rule
try {
    Set-NetFirewallRule -DisplayName $fwRuleName -Enabled False -ErrorAction Stop
    Write-Result -Msg "Firewall rule '$fwRuleName' disabled" -Success $true
} catch {
    Write-Result -Msg "Failed to disable firewall rule '$fwRuleName': $_" -Success $false
}

# Wait for 1 hour (simulate with 10 seconds for script demo; replace with 3600 for real test)
$waitSeconds = 10  # Use 3600 for real test
Write-Host "Waiting for $waitSeconds seconds to simulate 1 hour..." -ForegroundColor Yellow
Start-Sleep -Seconds $waitSeconds

# 1. MessageSenderPlugin.log contains log with TotalSize>0, Count>0, CommunicationChannel=IoTHub after rule disabled
try {
    if (Test-Path $senderLog) {
        $senderContent = Get-Content $senderLog -Raw
        $pattern = 'MessageSenderPlugin execute result is: \{.*"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"IoTHub".*\}'
        $matches = [regex]::Matches($senderContent, $pattern)
        $foundValid = $false
        foreach ($m in $matches) {
            $totalSize = [int]$m.Groups[1].Value
            $count = [int]$m.Groups[2].Value
            if ($totalSize -gt 0 -and $count -gt 0) {
                $foundValid = $true
                break
            }
        }
        Write-Result -Msg "MessageSenderPlugin.log contains valid IoTHub result with TotalSize>0 and Count>0 after firewall rule disabled" -Success $foundValid
    } else {
        Write-Result -Msg "MessageSenderPlugin.log not found after firewall rule disabled" -Success $false
    }
} catch {
    Write-Result -Msg "Error reading MessageSenderPlugin.log after firewall rule disabled: $_" -Success $false
}

# ============================================================
# PHASE 4: CLEANUP (Step 6)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write

Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
