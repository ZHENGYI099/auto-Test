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
# Step 2: Press “Win + E” keys, open File Explorer, go to the folder w
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 2: Press “Win + E” keys, open File Explorer, go to the folder w..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Start-Process -FilePath 'explorer.exe' -ArgumentList 'C:\VMShare'
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=2; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=2; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verification: (None)" -ForegroundColor Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 3: In file explorer, click on “File -> Open Windows PowerShell 
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 3: In file explorer, click on “File -> Open Windows PowerShell ..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WorkingDirectory 'C:\VMShare'
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=3; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=3; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verification: (None)" -ForegroundColor Gray

Start-Sleep -Milliseconds 300

# ======================================================================
# Step 4: Run command: msiexec /i cmdextension.msi /qn+
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 4: Run command: msiexec /i cmdextension.msi /qn+..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i','"cmdextension.msi"','/qn+','/l*v','"C:\VMShare\cmdextension-install.log"' -Wait -PassThru -NoNewWindow
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
    $s = Get-WmiObject -Class Win32_Service -Filter "Name='CloudManagedDesktopExtension'"; if ($s -and $s.State -eq 'Running') {$verifyExitCode=0} else {$verifyExitCode=1}
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
# Step 5: Open “Control Panel -> Programs -> Uninstall a program”
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 5: Open “Control Panel -> Programs -> Uninstall a program”..." -ForegroundColor Cyan
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
# Step 6: Open “Task Manager -> Services”
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 6: Open “Task Manager -> Services”..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $svc = Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -eq 'Running') {$verifyExitCode=0} else {$verifyExitCode=1}
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
# Step 7: Press “Win + R” keys, type “services.msc” and press Enter.
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 7: Press “Win + R” keys, type “services.msc” and press Enter...." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    $s=Get-WmiObject -Class Win32_Service -Filter "Name='CloudManagedDesktopExtension'"; if ($s -and $s.State -eq 'Running' -and $s.StartMode -eq 'Auto' -and ($s.DelayedAutoStart -eq $true) -and $s.StartName -eq 'LocalSystem') {$verifyExitCode=0} else {$verifyExitCode=1}
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
# Step 8: Open file explorer, go to %ProgramData%\Microsoft\CMDExtensi
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 8: Open file explorer, go to %ProgramData%\Microsoft\CMDExtensi..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"%ProgramData%\Microsoft\CMDExtension\Logs`"" -WorkingDirectory 'C:\VMShare'
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=8; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=8; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    if (Test-Path 'C:\ProgramData\Microsoft\CMDExtension\Logs\CMDExtension.log') {$verifyExitCode=0} else {$verifyExitCode=1}
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
# Step 9: Press “Win + R” keys, type “taskschd.msc” and press Enter. O
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 9: Press “Win + R” keys, type “taskschd.msc” and press Enter. O..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray

Write-Host "Verifying..." -ForegroundColor Yellow
try {
    $verifyExitCode=1
    if (Get-ScheduledTask -TaskName 'Cloud Managed Desktop Extension Health Evaluation' -TaskPath '\Microsoft\CMD\' -ErrorAction SilentlyContinue) {$verifyExitCode=0} else {$verifyExitCode=1}
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
# Step 10: Press “Win + R” keys, type “wbemtest” and press Enter. Click
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 10: Press “Win + R” keys, type “wbemtest” and press Enter. Click..." -ForegroundColor Cyan
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
# Step 11: Test Cleanup:   In the same PowerShell window as “Step 3”, r
# ======================================================================

Write-Host ("-"*60) -ForegroundColor Gray
Write-Host "Step 11: Test Cleanup:   In the same PowerShell window as “Step 3”, r..." -ForegroundColor Cyan
Write-Host ("-"*60) -ForegroundColor Gray

Write-Host "Executing Action..." -ForegroundColor Yellow
try {
    Set-Location -LiteralPath 'C:\VMShare'; $process=Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x',"`"cmdextension.msi`"",'/qn','/l*v',"`"C:\VMShare\cmdextension_uninstall.log`"" -Wait -PassThru -NoNewWindow; $exitCode=$process.ExitCode
    Write-Host "    [OK] Action succeeded" -ForegroundColor Green
    $script:results += @{Step=11; Action="Success"}
} catch {
    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $script:results += @{Step=11; Action="Failed"}
}

Start-Sleep -Seconds 2

Write-Host "Verification: (None)" -ForegroundColor Gray

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