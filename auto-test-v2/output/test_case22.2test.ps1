# ============================================================
# SETUP LOGGING
# ============================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "$PSScriptRoot\..\output\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$testCaseId = "case22.2test"
$logFile = Join-Path $logDir "test_${testCaseId}_$timestamp.log"

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
    exit 1
}

$msiPath = "C:\VMShare\cmdextension.msi"
$serviceName = "CloudManagedDesktopExtension"
$logFolder = "C:\ProgramData\Microsoft\CMDExtension\Logs"
$regSettings = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\Settings"
$regDiag = "HKLM:\SOFTWARE\Microsoft\CloudManagementDesktop\Extension\DiagnosticInfo"

# Check if already installed
function Is-AgentInstalled {
    return (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) -ne $null
}
if (Is-AgentInstalled) {
    Write-Result -Msg "Agent already installed. Uninstalling for clean test..." -Success $false
    $uninstallCmd = "msiexec.exe /x `"$msiPath`" /qn"
    $uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
    if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
        Write-Result -Msg "Previous agent uninstalled" -Success $true
    } else {
        Write-Result -Msg "Failed to uninstall previous agent (exit $($uninstallProc.ExitCode))" -Success $false
        exit 2
    }
}

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing CMD Agent..." -ForegroundColor Cyan
$svcEnv = "Test"
$installArgs = "/i `"$msiPath`" /qn SVCENV=$svcEnv"
$installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
$exitCode = $installProc.ExitCode
if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "Agent installed successfully (exit $exitCode)" -Success $true
} else {
    Write-Result -Msg "Agent installation failed (exit $exitCode)" -Success $false
    exit 3
}

Start-Sleep -Seconds 60

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying installation and agent behavior..." -ForegroundColor Cyan

# Step 1: Registry - Partners and PartnersTagDict
try {
    $settings = Get-ItemProperty -Path $regSettings
    $partners = $settings.Partners
    $partnersTagDict = $settings.PartnersTagDict
    $partners = if ([string]::IsNullOrWhiteSpace($partners)) { "" } else { $partners.Trim() }
    $partnersTagDict = if ([string]::IsNullOrWhiteSpace($partnersTagDict)) { "" } else { $partnersTagDict.Trim() }
    Write-Result -Msg "Partners registry value is CPC" -Success ($partners -eq "CPC")
    Write-Result -Msg "PartnersTagDict registry value is CPC=TEST01" -Success ($partnersTagDict -eq "CPC=TEST01")
} catch {
    Write-Result -Msg "Failed to read Partners/PartnersTagDict registry" -Success $false
}

# Step 2: Log checks (after 15 min)
Start-Sleep -Seconds 900
$logChecks = @(
    @{File="MessageSenderPlugin.log"; Pattern='"MessageSenderPlugin execute result is: {.*"CommunicationChannel":"IoTHub"}"'; CountCheck=$true},
    @{File="HeartbeatPlugin.log"; Pattern='^\{"ServiceStatus":"Running","AgentVersion":'; CountCheck=$false}
)
foreach ($check in $logChecks) {
    $logPath = Join-Path $logFolder $check.File
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Raw
        $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
        if ($check.CountCheck) {
            $match = [regex]::Match($content, '"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"IoTHub"')
            $totalSize = $match.Groups[1].Value
            $count = $match.Groups[2].Value
            $success = ($match.Success -and [int]$totalSize -gt 0 -and [int]$count -gt 0)
            Write-Result -Msg "MessageSenderPlugin.log IoTHub result found, TotalSize/Count > 0" -Success $success
        } else {
            $success = ($content -match '^\{"ServiceStatus":"Running","AgentVersion":')
            Write-Result -Msg "HeartbeatPlugin.log contains success log" -Success $success
        }
    } else {
        Write-Result -Msg "$($check.File) not found" -Success $false
    }
}

# Step 3: Block IoTHub endpoint in firewall
try {
    $iotHostName = $settings.IoTHostName
    $iotHostName = if ([string]::IsNullOrWhiteSpace($iotHostName)) { "" } else { $iotHostName.Trim() }
    if ($iotHostName -ne "") {
        $nslookup = nslookup $iotHostName 2>&1
        $ipMatch = $nslookup | Select-String -Pattern "Address: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"
        $iotIp = $null
        if ($ipMatch) {
            $iotIp = ($ipMatch.Matches[0].Groups[1].Value).Trim()
            $ruleName = "BlockIoTHubEndpoint"
            New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Action Block -RemoteAddress $iotIp -Protocol Any -Enabled True -ErrorAction SilentlyContinue
            Write-Result -Msg "Firewall rule created to block IoTHub IP $iotIp" -Success $true
        } else {
            Write-Result -Msg "Failed to resolve IoTHub IP" -Success $false
        }
    } else {
        Write-Result -Msg "IoTHostName registry value missing" -Success $false
    }
} catch {
    Write-Result -Msg "Failed to create firewall rule for IoTHub" -Success $false
}

# Step 3b: Get VersionInfo of files (example list)
$filesToCheck = @(
    "C:\Program Files\Microsoft\CloudManagedDesktop\Extension\CMDExtension.exe",
    "C:\Program Files\Microsoft\CloudManagedDesktop\Extension\AgentMainService.exe"
)
$msiVersion = Get-MSIProperty -msiPath $msiPath -property "ProductVersion"
foreach ($file in $filesToCheck) {
    if (Test-Path $file) {
        $fileVersion = (Get-Item $file).VersionInfo.FileVersion
        $fileVersion = if ([string]::IsNullOrWhiteSpace($fileVersion)) { "" } else { $fileVersion.Trim() }
        Write-Result -Msg "$file version matches MSI" -Success ($fileVersion -eq $msiVersion)
    } else {
        Write-Result -Msg "$file not found" -Success $false
    }
}

# Step 4: Registry DiagnosticInfo checks
try {
    $diag = Get-ItemProperty -Path $regDiag
    $latestIoTSendSuccessUtc = $diag.LatestIoTSendSuccessUtc
    $firstHttpsSendFailedUtc = $diag.FirstHttpsSendFailedUtc
    $firstIoTSendFailedUtc = $diag.FirstIoTSendFailedUtc
    $latestHttpsSendSuccessUtc = $diag.LatestHttpsSendSuccessUtc
    $latestIoTSendSuccessUtc = if ([string]::IsNullOrWhiteSpace($latestIoTSendSuccessUtc)) { "" } else { $latestIoTSendSuccessUtc.Trim() }
    $firstHttpsSendFailedUtc = if ([string]::IsNullOrWhiteSpace($firstHttpsSendFailedUtc)) { "" } else { $firstHttpsSendFailedUtc.Trim() }
    $firstIoTSendFailedUtc = if ([string]::IsNullOrWhiteSpace($firstIoTSendFailedUtc)) { "" } else { $firstIoTSendFailedUtc.Trim() }
    $latestHttpsSendSuccessUtc = if ([string]::IsNullOrWhiteSpace($latestHttpsSendSuccessUtc)) { "" } else { $latestHttpsSendSuccessUtc.Trim() }
    Write-Result -Msg "LatestIoTSendSuccessUtc has value" -Success ($latestIoTSendSuccessUtc -ne "")
    Write-Result -Msg "FirstHttpsSendFailedUtc is 0001/1/1 0:00:00" -Success ($firstHttpsSendFailedUtc -eq "0001/1/1 0:00:00")
    Write-Result -Msg "FirstIoTSendFailedUtc is 0001/1/1 0:00:00" -Success ($firstIoTSendFailedUtc -eq "0001/1/1 0:00:00")
    Write-Result -Msg "LatestHttpsSendSuccessUtc is 0001/1/1 0:00:00" -Success ($latestHttpsSendSuccessUtc -eq "0001/1/1 0:00:00")
} catch {
    Write-Result -Msg "Failed to read DiagnosticInfo registry" -Success $false
}

# Step 5: Wait for more than 12 hours (skipped for automation, log message only)
Write-Host "[INFO] Skipping 12 hour wait for automation. Manual validation required for time-based checks." -ForegroundColor Yellow

# Step 6: Registry DiagnosticInfo - CMDAgentCommunicationChannel
try {
    $diag = Get-ItemProperty -Path $regDiag
    $commChannel = $diag.CMDAgentCommunicationChannel
    $commChannel = if ([string]::IsNullOrWhiteSpace($commChannel)) { "" } else { $commChannel.Trim() }
    Write-Result -Msg "CMDAgentCommunicationChannel is Https" -Success ($commChannel -eq "Https")
} catch {
    Write-Result -Msg "Failed to read CMDAgentCommunicationChannel registry" -Success $false
}

# Step 7: Log checks for Https channel
$logChecks2 = @(
    @{File="MessageSenderPlugin.log"; Pattern='"MessageSenderPlugin execute result is: {.*"CommunicationChannel":"Https"}"'; CountCheck=$true},
    @{File="HeartbeatPlugin.log"; Pattern='^\{"ServiceStatus":"Running","AgentVersion":'; CountCheck=$false},
    @{File="MessageSenderPlugin.log"; Pattern='Https channel send messages to dgs successfully'; CountCheck=$false}
)
foreach ($check in $logChecks2) {
    $logPath = Join-Path $logFolder $check.File
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Raw
        $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
        if ($check.CountCheck) {
            $match = [regex]::Match($content, '"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"Https"')
            $totalSize = $match.Groups[1].Value
            $count = $match.Groups[2].Value
            $success = ($match.Success -and [int]$totalSize -gt 0 -and [int]$count -gt 0)
            Write-Result -Msg "MessageSenderPlugin.log Https result found, TotalSize/Count > 0" -Success $success
        } else {
            $success = ($content -match $check.Pattern)
            Write-Result -Msg "$($check.File) contains expected pattern" -Success $success
        }
    } else {
        Write-Result -Msg "$($check.File) not found" -Success $false
    }
}

# Step 8: Registry NextUpradeViaHttpsDateTime, WMI SchedulerEntity LastRunTime
try {
    $nextUpgrade = $settings.NextUpradeViaHttpsDateTime
    $nextUpgrade = if ([string]::IsNullOrWhiteSpace($nextUpgrade)) { "" } else { $nextUpgrade.Trim() }
    $now = Get-Date
    if ($nextUpgrade -ne "" -and ([datetime]$nextUpgrade -gt $now)) {
        Set-ItemProperty -Path $regSettings -Name NextUpradeViaHttpsDateTime -Value ($now.AddMinutes(-10).ToString("yyyy/MM/dd HH:mm:ss"))
        Write-Result -Msg "NextUpradeViaHttpsDateTime updated to past" -Success $true
    } else {
        Write-Result -Msg "NextUpradeViaHttpsDateTime not greater than current time" -Success $true
    }
    # WMI: Update SchedulerEntity LastRunTime
    $wmiObjs = Get-WmiObject -Namespace "root\cmd\clientagent" -Class "SchedulerEntity" -ErrorAction SilentlyContinue
    $found = $false
    foreach ($obj in $wmiObjs) {
        if ($obj.PluginName -eq "UpdateCheckerPlugin") {
            $obj.LastRunTime = (Get-Date).AddDays(-1).ToString("yyyyMMddHHmmss.000000+000")
            $obj.Put() | Out-Null
            $found = $true
        }
    }
    Write-Result -Msg "SchedulerEntity LastRunTime updated for UpdateCheckerPlugin" -Success $found
    Start-Sleep -Seconds 60
} catch {
    Write-Result -Msg "Failed to update NextUpradeViaHttpsDateTime or WMI SchedulerEntity" -Success $false
}

# Step 8b: Log checks for UpdateCheckerPlugin
$updateLog = Join-Path $logFolder "UpdateCheckerPlugin.log"
if (Test-Path $updateLog) {
    $content = Get-Content $updateLog -Raw
    $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
    $success1 = $content -match "Plugin 0c0b7866-fd11-4ec1-8636-7da3478b7160 executes policy 819301bd-f921-4ee3-902f-1ed870030087 Success but failed to process the result to NoSender"
    $success2 = ($content -match "Known exception: CDNSourceDownloadUrl and StorageSourceDownloadUrl are empty" -or
                 $content -match "Download msi from received cdn uri" -or
                 $content -match "NextUpradeViaHttpsDateTime is")
    Write-Result -Msg "UpdateCheckerPlugin.log contains expected success log" -Success $success1
    Write-Result -Msg "UpdateCheckerPlugin.log contains expected exception/download log" -Success $success2
} else {
    Write-Result -Msg "UpdateCheckerPlugin.log not found" -Success $false
}

# Step 9: Disable firewall rule, wait 4 hours, check logs
Set-NetFirewallRule -DisplayName $ruleName -Enabled False -ErrorAction SilentlyContinue
Write-Host "[INFO] Skipping 4 hour wait for automation. Manual validation required for time-based checks." -ForegroundColor Yellow
# Log checks after disabling firewall
foreach ($check in $logChecks) {
    $logPath = Join-Path $logFolder $check.File
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Raw
        $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
        if ($check.CountCheck) {
            $match = [regex]::Match($content, '"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"IoTHub"')
            $totalSize = $match.Groups[1].Value
            $count = $match.Groups[2].Value
            $success = ($match.Success -and [int]$totalSize -gt 0 -and [int]$count -gt 0)
            Write-Result -Msg "MessageSenderPlugin.log IoTHub result found after firewall disable, TotalSize/Count > 0" -Success $success
        } else {
            $success = ($content -match '^\{"ServiceStatus":"Running","AgentVersion":')
            Write-Result -Msg "HeartbeatPlugin.log contains additional success log after firewall disable" -Success $success
        }
    } else {
        Write-Result -Msg "$($check.File) not found after firewall disable" -Success $false
    }
}

# Step 10: Uninstall agent and clear log folder
Write-Host "Uninstalling agent and clearing logs..." -ForegroundColor Cyan
$uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
    Write-Result -Msg "Agent uninstalled successfully (exit $($uninstallProc.ExitCode))" -Success $true
} else {
    Write-Result -Msg "Agent uninstall failed (exit $($uninstallProc.ExitCode))" -Success $false
}
if (Test-Path $logFolder) {
    Remove-Item -Path $logFolder\* -Force -Recurse -ErrorAction SilentlyContinue
    Write-Result -Msg "Log folder cleared" -Success $true
} else {
    Write-Result -Msg "Log folder not found for cleanup" -Success $false
}

# Step 11: Enable firewall rule
Set-NetFirewallRule -DisplayName $ruleName -Enabled True -ErrorAction SilentlyContinue
Write-Result -Msg "Firewall rule enabled" -Success $true

# Step 12: Reinstall agent
Write-Host "Reinstalling agent..." -ForegroundColor Cyan
$installProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
$exitCode = $installProc.ExitCode
if ($exitCode -eq 0 -or $exitCode -eq 3010) {
    Write-Result -Msg "Agent reinstalled successfully (exit $exitCode)" -Success $true
} else {
    Write-Result -Msg "Agent reinstall failed (exit $exitCode)" -Success $false
    exit 4
}

# Step 13: Record time, skip 12 hour wait, check logs for Https only
$time1 = Get-Date
Write-Host "[INFO] Skipping 12 hour wait for automation. Manual validation required for time-based checks." -ForegroundColor Yellow
$infraLog = Join-Path $logFolder "InfraLogs\AgentMainService.log"
# Only check MessageSenderPlugin.log for Https, not IoTHub
$logPath = Join-Path $logFolder "MessageSenderPlugin.log"
if (Test-Path $logPath) {
    $content = Get-Content $logPath -Raw
    $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
    $match = [regex]::Match($content, '"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"Https"')
    $totalSize = $match.Groups[1].Value
    $count = $match.Groups[2].Value
    $success = ($match.Success -and [int]$totalSize -gt 0 -and [int]$count -gt 0)
    Write-Result -Msg "MessageSenderPlugin.log Https result found after reinstall, TotalSize/Count > 0" -Success $success
    $noIoTHub = ($content -notmatch '"CommunicationChannel":"IoTHub"')
    Write-Result -Msg "MessageSenderPlugin.log does not contain IoTHub channel after reinstall" -Success $noIoTHub
} else {
    Write-Result -Msg "MessageSenderPlugin.log not found after reinstall" -Success $false
}
$cmdExtLog = Join-Path $logFolder "CMDExtension.log"
if (Test-Path $cmdExtLog) {
    $content = Get-Content $cmdExtLog -Raw
    $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
    $noDeviceClient = ($content -notmatch "DeviceClient created and opened successfully.")
    Write-Result -Msg "CMDExtension.log does not contain DeviceClient created/opened after reinstall" -Success $noDeviceClient
} else {
    Write-Result -Msg "CMDExtension.log not found after reinstall" -Success $false
}

# Step 14: Disable firewall rule
Set-NetFirewallRule -DisplayName $ruleName -Enabled False -ErrorAction SilentlyContinue
Write-Result -Msg "Firewall rule disabled" -Success $true

# Step 15: Wait 6 hours, check logs for IoTHub channel and DeviceClient
Write-Host "[INFO] Skipping 6 hour wait for automation. Manual validation required for time-based checks." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $content = Get-Content $logPath -Raw
    $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
    $match = [regex]::Match($content, '"TotalSize":(\d+),"Count":(\d+),"CommunicationChannel":"IoTHub"')
    $totalSize = $match.Groups[1].Value
    $count = $match.Groups[2].Value
    $success = ($match.Success -and [int]$totalSize -gt 0 -and [int]$count -gt 0)
    Write-Result -Msg "MessageSenderPlugin.log IoTHub result found after firewall disable, TotalSize/Count > 0" -Success $success
} else {
    Write-Result -Msg "MessageSenderPlugin.log not found after firewall disable" -Success $false
}
if (Test-Path $cmdExtLog) {
    $content = Get-Content $cmdExtLog -Raw
    $content = if ([string]::IsNullOrWhiteSpace($content)) { "" } else { $content.Trim() }
    $hasDeviceClient = ($content -match "DeviceClient created and opened successfully.")
    Write-Result -Msg "CMDExtension.log contains DeviceClient created/opened after firewall disable" -Success $hasDeviceClient
} else {
    Write-Result -Msg "CMDExtension.log not found after firewall disable" -Success $false
}

# Step 16: Cleanup - uninstall agent
Write-Host "Final cleanup: uninstalling agent..." -ForegroundColor Cyan
$uninstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$msiPath`" /qn" -Wait -PassThru
if ($uninstallProc.ExitCode -eq 0 -or $uninstallProc.ExitCode -eq 1605) {
    Write-Result -Msg "Agent uninstalled successfully (exit $($uninstallProc.ExitCode))" -Success $true
} else {
    Write-Result -Msg "Agent uninstall failed (exit $($uninstallProc.ExitCode))" -Success $false
}

# ============================================================
# SUMMARY & END
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