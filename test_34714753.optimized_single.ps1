# Test Execution Script - All steps in one session
$ErrorActionPreference = "Continue"

Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "Test Execution Started" -ForegroundColor Cyan
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host ''

$script:results = @()

# ======================================================================
# Step 1: Apply to all devices.
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 1: Apply to all devices...." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verification: (None)" -ForegroundColor Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 2: Press 'Win + E' keys, open File Explorer, go to the folder w
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 2: Press 'Win + E' keys, open File Explorer, go to the folder w..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Set-Location -LiteralPath 'C:\VMShare'
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=2; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=2; Action="Failed"}
}

Write-Host "Verification: (None)" -ForegroundColor Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 3: Verify administrator privileges (script already running as a
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 3: Verify administrator privileges (script already running as a..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    $isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($isAdmin) {Write-Host 'Running as Administrator'} else {Write-Host 'WARNING: Not running as Administrator'}
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=3; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=3; Action="Failed"}
}

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($isAdmin) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=3; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=3; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=3; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 4: Run command: msiexec /i cmdextension.msi /qn (silent install
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 4: Run command: msiexec /i cmdextension.msi /qn (silent install..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    $msiPath='C:\VMShare\cmdextension.msi'; $msiLogPath="$PSScriptRoot\outputs\msi_install_$(Get-Date -Format 'yyyyMMddHHmmss').log"; $process=Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i',"`"$msiPath`"",'/qn','/l*v',"`"$msiLogPath`"" -Wait -PassThru -NoNewWindow; $exitCode=$process.ExitCode; if ($exitCode -eq 0 -or $exitCode -eq 3010) {Write-Host "Installation successful (exit code: $exitCode)"} else {Write-Host "Installation completed with exit code: $exitCode. Check log: $msiLogPath"}
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=4; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=4; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $svc=Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if ($svc) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=4; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=4; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=4; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 5: Open 'Control Panel -> Programs -> Uninstall a program'
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 5: Open 'Control Panel -> Programs -> Uninstall a program'..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    if (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object {$_.DisplayName -like '*Microsoft Cloud Managed Desktop Extension*'}) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=5; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=5; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=5; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 6: Open 'Task Manager -> Services'
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 6: Open 'Task Manager -> Services'..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $svc=Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -eq 'Running') {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=6; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=6; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=6; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 7: Press 'Win + R' keys, type 'services.msc' and press Enter.
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 7: Press 'Win + R' keys, type 'services.msc' and press Enter...." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $s=Get-WmiObject -Class Win32_Service -Filter "Name='CloudManagedDesktopExtension'"; if ($s -and $s.State -eq 'Running' -and $s.StartMode -eq 'Auto' -and $s.StartName -eq 'LocalSystem') {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=7; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=7; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=7; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 8: Verify log file exists in %ProgramData%\Microsoft\CMDExtensi
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 8: Verify log file exists in %ProgramData%\Microsoft\CMDExtensi..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $logPath="$env:ProgramData\Microsoft\CMDExtension\Logs\CMDExtension.log"; if (Test-Path $logPath) {$fileInfo=Get-Item $logPath; Write-Host "Log file found: Size=$($fileInfo.Length) bytes"; $verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=8; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=8; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=8; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 9: Press 'Win + R' keys, type 'taskschd.msc' and press Enter. O
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 9: Press 'Win + R' keys, type 'taskschd.msc' and press Enter. O..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $task = Get-ScheduledTask -TaskName 'Cloud Managed Desktop Extension Health Evaluation' -ErrorAction SilentlyContinue; if ($task) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=9; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=9; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=9; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 10: Press 'Win + R' keys, type 'wbemtest' and press Enter. Click
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 10: Press 'Win + R' keys, type 'wbemtest' and press Enter. Click..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    if ((Get-WmiObject -Namespace 'root\cmd\clientagent' -List -ErrorAction SilentlyContinue)) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=10; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=10; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=10; Verify="Failed"}
}

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 11: Test Cleanup: Run command: msiexec /x cmdextension.msi /qn (
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 11: Test Cleanup: Run command: msiexec /x cmdextension.msi /qn (..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    $msiPath='C:\VMShare\cmdextension.msi'; $uninstallLogPath="$PSScriptRoot\outputs\msi_uninstall_$(Get-Date -Format 'yyyyMMddHHmmss').log"; $process=Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x',"`"$msiPath`"",'/qn','/l*v',"`"$uninstallLogPath`"" -Wait -PassThru -NoNewWindow; $exitCode=$process.ExitCode; if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1605) {Write-Host "Uninstallation successful (exit code: $exitCode)"} else {Write-Host "Uninstallation completed with exit code: $exitCode. Check log: $uninstallLogPath"}
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=11; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=11; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $svc=Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if (!$svc) {$verifyExitCode=0} else {$verifyExitCode=1}
    if ($verifyExitCode -eq 0) {
        Write-Host "    [OK] Verification passed" -ForegroundColor Green
        $script:results += @{Step=11; Verify="Success"}
    } else {
        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red
        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red
        Write-Host ")" -ForegroundColor Red
        $script:results += @{Step=11; Verify="Failed"}
    }
} catch {
    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=11; Verify="Failed"}
}

Start-Sleep -Milliseconds 300


Write-Host ''
Write-Host ("="*80) -ForegroundColor Green
Write-Host "Test Execution Completed - Summary" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Green
Write-Host ''
$successCount = ($script:results | Where-Object { $_.Action -eq "Success" -or $_.Verify -eq "Success" }).Count
$failedCount = ($script:results | Where-Object { $_.Action -eq "Failed" -or $_.Verify -eq "Failed" }).Count
Write-Host "Success: " -NoNewline -ForegroundColor Green
Write-Host $successCount -ForegroundColor Green
Write-Host "Failed: " -NoNewline -ForegroundColor Red
Write-Host $failedCount -ForegroundColor Red
Write-Host ''
Write-Host "Press Enter to close" -ForegroundColor Yellow
pause