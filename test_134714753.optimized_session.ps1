# Auto-generated test execution script
$ErrorActionPreference = 'Continue'

# ======================================================================
# Step 1: Apply to all devices.
# ======================================================================

Write-Host '⚙️  Step 1 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 1 Verify: (None)' -ForegroundColor Gray

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 2: Press “Win + E” keys, open File Explorer, go to the folder w
# ======================================================================

Write-Host '⚙️  Step 2 Action:' -ForegroundColor Cyan
try {
    Set-Location -LiteralPath 'C:\VMShare'
    Write-Host '    ✅ Action completed' -ForegroundColor Green
} catch {
    Write-Host '    ❌ Action failed: ' $_.Exception.Message -ForegroundColor Red
}

Write-Host '🔬 Step 2 Verify: (None)' -ForegroundColor Gray

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 3: In file explorer, click on “File -> Open Windows PowerShell 
# ======================================================================

Write-Host '⚙️  Step 3 Action:' -ForegroundColor Cyan
try {
    Start-Process powershell.exe -Verb RunAs -WorkingDirectory 'C:\VMShare'
    Write-Host '    ✅ Action completed' -ForegroundColor Green
} catch {
    Write-Host '    ❌ Action failed: ' $_.Exception.Message -ForegroundColor Red
}

Write-Host '🔬 Step 3 Verify: (None)' -ForegroundColor Gray

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 4: Run command: msiexec /i cmdextension.msi /qn+
# ======================================================================

Write-Host '⚙️  Step 4 Action:' -ForegroundColor Cyan
try {
    Start-Process msiexec.exe -ArgumentList '/i cmdextension.msi /qn+' -Wait -WorkingDirectory 'C:\VMShare'
    Write-Host '    ✅ Action completed' -ForegroundColor Green
} catch {
    Write-Host '    ❌ Action failed: ' $_.Exception.Message -ForegroundColor Red
}

Write-Host '🔬 Step 4 Verify: Manual verification required' -ForegroundColor Yellow

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 5: Open “Control Panel -> Programs -> Uninstall a program”
# ======================================================================

Write-Host '⚙️  Step 5 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 5 Verify:' -ForegroundColor Cyan
try {
    if (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object {$_.DisplayName -like '*Microsoft Cloud Managed Desktop Extension*'}) {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 6: Open “Task Manager -> Services”
# ======================================================================

Write-Host '⚙️  Step 6 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 6 Verify:' -ForegroundColor Cyan
try {
    $svc = Get-Service -Name 'CloudManagedDesktopExtension' -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -eq 'Running') {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 7: Press “Win + R” keys, type “services.msc” and press Enter.
# ======================================================================

Write-Host '⚙️  Step 7 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 7 Verify:' -ForegroundColor Cyan
try {
    $s=Get-WmiObject -Class Win32_Service -Filter "Name='cmdextension'"; if ($s -and $s.State -eq 'Running' -and $s.StartMode -eq 'Auto' -and $s.DelayedAutoStart -eq $true -and $s.StartName -eq 'LocalSystem') {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 8: Open file explorer, go to %ProgramData%\Microsoft\CMDExtensi
# ======================================================================

Write-Host '⚙️  Step 8 Action:' -ForegroundColor Cyan
try {
    Start-Process explorer.exe -ArgumentList "`"%ProgramData%\Microsoft\CMDExtension\Logs`"" -WorkingDirectory 'C:\VMShare'
    Write-Host '    ✅ Action completed' -ForegroundColor Green
} catch {
    Write-Host '    ❌ Action failed: ' $_.Exception.Message -ForegroundColor Red
}

Write-Host '🔬 Step 8 Verify:' -ForegroundColor Cyan
try {
    if (Test-Path 'C:\ProgramData\Microsoft\CMDExtension\Logs\CMDExtension.log') {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 9: Press “Win + R” keys, type “taskschd.msc” and press Enter. O
# ======================================================================

Write-Host '⚙️  Step 9 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 9 Verify:' -ForegroundColor Cyan
try {
    $task = Get-ScheduledTask -TaskName 'Cloud Managed Desktop Extension Health Evaluation' -ErrorAction SilentlyContinue; if ($task) {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 10: Press “Win + R” keys, type “wbemtest” and press Enter. Click
# ======================================================================

Write-Host '⚙️  Step 10 Action: (Empty - skipped)' -ForegroundColor Gray

Write-Host '🔬 Step 10 Verify:' -ForegroundColor Cyan
try {
    if ((Get-WmiObject -Namespace 'root\cmd\clientagent' -List -ErrorAction SilentlyContinue)) {exit 0} else {exit 1}
    if ($LASTEXITCODE -eq 0) {
        Write-Host '    ✅ Verification passed' -ForegroundColor Green
    } else {
        Write-Host '    ❌ Verification failed (exit code: ' $LASTEXITCODE ')' -ForegroundColor Red
    }
} catch {
    Write-Host '    ❌ Verification failed: ' $_.Exception.Message -ForegroundColor Red
}

Start-Sleep -Milliseconds 500

# ======================================================================
# Step 11: Test Cleanup:


In the same PowerShell window as “Step 3”, r
# ======================================================================

Write-Host '⚙️  Step 11 Action:' -ForegroundColor Cyan
try {
    Set-Location -LiteralPath 'C:\VMShare'; msiexec /x cmdextension.msi
    Write-Host '    ✅ Action completed' -ForegroundColor Green
} catch {
    Write-Host '    ❌ Action failed: ' $_.Exception.Message -ForegroundColor Red
}

Write-Host '🔬 Step 11 Verify: (None)' -ForegroundColor Gray

Start-Sleep -Milliseconds 500

Write-Host ''
Write-Host '='*80 -ForegroundColor Green
Write-Host '✅ All steps executed' -ForegroundColor Green
Write-Host '='*80 -ForegroundColor Green