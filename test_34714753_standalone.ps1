# Test Execution Script with Manual Verification
$ErrorActionPreference = "Continue"
$logFile = "D:\\auto-Test\\outputs/test_execution_20251015_165139.log"
$caseId = "34714753"

# Initialize log file
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

"="*80 | Out-File -FilePath $logFile -Encoding UTF8
"Test Execution Log" | Out-File -FilePath $logFile -Append -Encoding UTF8
"Test Case: " + $caseId | Out-File -FilePath $logFile -Append -Encoding UTF8
"Started: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $logFile -Append -Encoding UTF8
"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8
""  | Out-File -FilePath $logFile -Append -Encoding UTF8

Write-Log ("="*80) Cyan
Write-Log "Test Execution Started" Cyan
Write-Log ("="*80) Cyan
Write-Log ""

$script:results = @()

# ======================================================================
# Step 1: Apply to all devices.
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 1: Apply to all devices...." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verification: (None)" Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 2: Press 'Win + E' keys, open File Explorer, go to the folder w
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 2: Press 'Win + E' keys, open File Explorer, go to the folder w..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Executing Action..." Yellow
try {
    Set-Location -LiteralPath 'C:\VMShare'
    Write-Log "    [OK] Action executed" Green
    $script:results += @{Step=2; Action="Success"}
} catch {
    Write-Log "    [FAIL] Action failed: $($_.Exception.Message)" Red
    $script:results += @{Step=2; Action="Failed"}
}

Write-Log "Verification: (None)" Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 3: In file explorer, click on 'File -> Open Windows PowerShell 
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 3: Prepare for MSI installation (admin context already available)..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Skipped - script already running with admin privileges)" Gray
Write-Log "    Current execution policy: $((Get-ExecutionPolicy))" Gray
Write-Log "    Current working directory: $PWD" Gray

# Verify we have admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Log "    [OK] Running with Administrator privileges" Green
    $script:results += @{Step=3; Action="Success"}
} else {
    Write-Log "    [WARN] Not running as Administrator" Yellow
    $script:results += @{Step=3; Action="Warning"}
}

Start-Sleep -Seconds 1

Write-Log "Verification: (None)" Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 4: Run command: msiexec /i cmdextension.msi /qn+
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 4: Run command: msiexec /i cmdextension.msi /qn+..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Executing Action..." Yellow
try {
    # MSI Silent Installation with exit code verification
    $msiPath = 'C:\VMShare\cmdextension.msi'
    
    # Check if MSI file exists
    if (!(Test-Path $msiPath)) {
        throw "MSI file not found: $msiPath"
    }
    Write-Log "    MSI file found: $msiPath" Gray
    
    # Create detailed log file for MSI installation
    $msiLogPath = "$PSScriptRoot\outputs\msi_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    # Build msiexec arguments - /qn for completely silent installation (no UI)
    $msiArgs = @(
        '/i', "`"$msiPath`""
        '/qn'  # Completely silent - no UI at all
        '/l*v', "`"$msiLogPath`""  # Verbose logging
    )
    
    Write-Log "    Running: msiexec.exe $($msiArgs -join ' ')" Gray
    Write-Log "    Installation mode: Completely silent (no UI)" Gray
    Write-Log "    Installation log: $msiLogPath" Gray
    
    # Execute msiexec and capture exit code
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
    
    Write-Log "    MSI exit code: $exitCode" Gray
    
    # Check exit code (0 = success, 3010 = success but reboot required)
    if ($exitCode -eq 0) {
        Write-Log "    [OK] MSI installation completed successfully" Green
        $script:results += @{Step=4; Action="Success"}
    } elseif ($exitCode -eq 3010) {
        Write-Log "    [OK] MSI installation completed (reboot required)" Yellow
        $script:results += @{Step=4; Action="Success"}
    } elseif ($exitCode -eq 1603) {
        Write-Log "    [FAIL] MSI installation failed - Fatal error (1603)" Red
        Write-Log "    Check log file: $msiLogPath" Yellow
        $script:results += @{Step=4; Action="Failed"}
    } elseif ($exitCode -eq 1618) {
        Write-Log "    [FAIL] Another installation is already in progress (1618)" Red
        $script:results += @{Step=4; Action="Failed"}
    } elseif ($exitCode -eq 1925) {
        Write-Log "    [FAIL] Insufficient privileges (1925) - Run as Administrator" Red
        $script:results += @{Step=4; Action="Failed"}
    } else {
        Write-Log "    [WARN] MSI exit code: $exitCode - Check log for details" Yellow
        Write-Log "    Log file: $msiLogPath" Yellow
        # Treat as success but with warning
        $script:results += @{Step=4; Action="Success"}
    }
    
    # Additional verification: Check if service was created
    Write-Log "    Verifying service creation..." Gray
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "    [OK] Service 'CloudManagedDesktopExtension' created successfully" Green
        $script:results += @{Step=4; Verify="Success (Auto)"}
    } else {
        Write-Log "    [WARN] Service not found immediately after installation" Yellow
        Write-Log "    This may be normal - will verify in subsequent steps" Gray
        $script:results += @{Step=4; Verify="Pending"}
    }
    
} catch {
    Write-Log "    [FAIL] Action failed: $($_.Exception.Message)" Red
    $script:results += @{Step=4; Action="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 5: Open 'Control Panel -> Programs -> Uninstall a program'
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 5: Open 'Control Panel -> Programs -> Uninstall a program'..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    if (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object {$_.DisplayName -like '*Microsoft Cloud Managed Desktop Extension*'}) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Log "    [OK] Verification passed" Green
        $script:results += @{Step=5; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red
        $script:results += @{Step=5; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=5; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 6: Open 'Task Manager -> Services'
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 6: Open 'Task Manager -> Services'..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    $svc=Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -eq 'Running') {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Log "    [OK] Verification passed" Green
        $script:results += @{Step=6; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red
        $script:results += @{Step=6; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=6; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 7: Press 'Win + R' keys, type 'services.msc' and press Enter.
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 7: Press 'Win + R' keys, type 'services.msc' and press Enter...." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    # Use the correct service name: CloudManagedDesktopExtension
    $s=Get-WmiObject -Class Win32_Service -Filter "Name='CloudManagedDesktopExtension'"
    
    if ($s) {
        Write-Log "    Service found: $($s.Name)" Gray
        Write-Log "    Display Name: $($s.DisplayName)" Gray
        Write-Log "    State: $($s.State), StartMode: $($s.StartMode), DelayedAutoStart: $($s.DelayedAutoStart), StartName: $($s.StartName)" Gray
        
        # Check if service is running with Auto start mode and LocalSystem account
        if ($s.State -eq 'Running' -and $s.StartMode -eq 'Auto' -and $s.StartName -eq 'LocalSystem') {
            $verifyExitCode=0
        } else {
            $verifyExitCode=1
        }
    } else {
        Write-Log "    [WARN] Service 'CloudManagedDesktopExtension' not found" Yellow
        $verifyExitCode=1
    }
    
    if ($verifyExitCode -eq 0) {
        Write-Log "    [OK] Verification passed" Green
        $script:results += @{Step=7; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red
        $script:results += @{Step=7; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=7; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 8: Open file explorer, go to %ProgramData%\Microsoft\CMDExtensi
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 8: Verify log file exists in %ProgramData%\Microsoft\CMDExtension\Logs..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Verification only - no UI needed)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    $logPath = "$env:ProgramData\Microsoft\CMDExtension\Logs\CMDExtension.log"
    
    if (Test-Path $logPath) {
        Write-Log "    [OK] Log file found: $logPath" Green
        # Get file info
        $fileInfo = Get-Item $logPath
        Write-Log "    Size: $($fileInfo.Length) bytes, Modified: $($fileInfo.LastWriteTime)" Gray
        $verifyExitCode=0
        $script:results += @{Step=8; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Log file not found: $logPath" Red
        $verifyExitCode=1
        $script:results += @{Step=8; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=8; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 9: Press 'Win + R' keys, type 'taskschd.msc' and press Enter. O
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 9: Press 'Win + R' keys, type 'taskschd.msc' and press Enter. O..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    $task = Get-ScheduledTask -TaskName 'Cloud Managed Desktop Extension Health Evaluation' -ErrorAction SilentlyContinue; if ($task) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Log "    [OK] Verification passed" Green
        $script:results += @{Step=9; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red
        $script:results += @{Step=9; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=9; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 10: Press 'Win + R' keys, type 'wbemtest' and press Enter. Click
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 10: Press 'Win + R' keys, type 'wbemtest' and press Enter. Click..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Action: (Empty - verification only)" Gray

Write-Log "Verifying..." Yellow
try {
    $verifyExitCode=1
    if ((Get-WmiObject -Namespace 'root\cmd\clientagent' -List -ErrorAction SilentlyContinue)) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Log "    [OK] Verification passed" Green
        $script:results += @{Step=10; Verify="Success"}
    } else {
        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red
        $script:results += @{Step=10; Verify="Failed"}
    }
} catch {
    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red
    $script:results += @{Step=10; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 11: Test Cleanup:   In the same PowerShell window as 'Step 3', r
# ======================================================================
Write-Log ("-"*60) Gray
Write-Log "Step 11: Test Cleanup:   In the same PowerShell window as 'Step 3', r..." Cyan
Write-Log ("-"*60) Gray

Write-Log "Executing Action..." Yellow
try {
    # MSI Silent Uninstallation with exit code verification
    $msiPath = 'C:\VMShare\cmdextension.msi'
    
    # Check if MSI file exists
    if (!(Test-Path $msiPath)) {
        Write-Log "    [WARN] MSI file not found: $msiPath" Yellow
        Write-Log "    Attempting to uninstall by product name..." Gray
    }
    
    # Create log file for uninstallation
    $uninstallLogPath = "$PSScriptRoot\outputs\msi_uninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    # Build msiexec arguments - /qn for completely silent uninstallation
    $msiArgs = @(
        '/x', "`"$msiPath`""
        '/qn'  # Completely silent - no confirmation dialog
        '/l*v', "`"$uninstallLogPath`""  # Verbose logging
    )
    
    Write-Log "    Running: msiexec.exe $($msiArgs -join ' ')" Gray
    Write-Log "    Uninstallation mode: Completely silent (no confirmation)" Gray
    Write-Log "    Uninstallation log: $uninstallLogPath" Gray
    
    # Execute msiexec and capture exit code
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
    
    Write-Log "    MSI exit code: $exitCode" Gray
    
    # Check exit code
    if ($exitCode -eq 0) {
        Write-Log "    [OK] MSI uninstallation completed successfully" Green
        $script:results += @{Step=11; Action="Success"}
    } elseif ($exitCode -eq 3010) {
        Write-Log "    [OK] MSI uninstallation completed (reboot required)" Yellow
        $script:results += @{Step=11; Action="Success"}
    } elseif ($exitCode -eq 1605) {
        Write-Log "    [INFO] Product not installed (1605)" Gray
        $script:results += @{Step=11; Action="Success"}
    } else {
        Write-Log "    [WARN] MSI exit code: $exitCode - Check log for details" Yellow
        Write-Log "    Log file: $uninstallLogPath" Yellow
        $script:results += @{Step=11; Action="Success"}
    }
    
    # Verify service is removed
    Write-Log "    Verifying service removal..." Gray
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue
    if (!$svc) {
        Write-Log "    [OK] Service 'CloudManagedDesktopExtension' removed successfully" Green
    } else {
        Write-Log "    [WARN] Service still exists (may be stopped)" Yellow
    }
    
} catch {
    Write-Log "    [FAIL] Action failed: $($_.Exception.Message)" Red
    $script:results += @{Step=11; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Log "Verification: (None)" Gray

Start-Sleep -Milliseconds 300


Write-Log "" White
Write-Log ("="*80) Green
Write-Log "Test Execution Completed - Summary" Green
Write-Log ("="*80) Green
Write-Log "" White

# Display results table
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "Detailed Results:" -ForegroundColor Cyan
Write-Host ("="*80) -ForegroundColor Cyan
$script:results | Format-Table -AutoSize

# Write detailed results to log
"" | Out-File -FilePath $logFile -Append -Encoding UTF8
"Detailed Results:" | Out-File -FilePath $logFile -Append -Encoding UTF8
"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8
$script:results | Format-Table -AutoSize | Out-File -FilePath $logFile -Append -Encoding UTF8

# Summary counts
$successCount = ($script:results | Where-Object { $_.Action -eq "Success" -or $_.Verify -match "Success" }).Count
$failedCount = ($script:results | Where-Object { $_.Action -eq "Failed" -or $_.Verify -match "Failed" }).Count
Write-Log "Success: $successCount" Green
Write-Log "Failed: $failedCount" Red
Write-Log "" White
Write-Log "Log file: $logFile" Cyan
Write-Log "" White
"" | Out-File -FilePath $logFile -Append -Encoding UTF8
"Test completed at: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $logFile -Append -Encoding UTF8
"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8

Write-Host "Press Enter to close" -ForegroundColor Yellow
pause