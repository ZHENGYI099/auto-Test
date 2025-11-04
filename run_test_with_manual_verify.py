"""
Test Executor with Manual Verification and Logging
- Execute all steps in ONE admin PowerShell session
- Manual confirmation for steps that need vision verification
- Log all results to file
"""
import json
import subprocess
from pathlib import Path
from datetime import datetime

def generate_script_with_manual_verify(steps, test_case_id, log_file):
    """Generate PowerShell script with manual verification support"""
    
    import os
    workspace_dir = os.path.abspath('.').replace('\\', '\\\\')
    
    lines = [
        "# Test Execution Script with Manual Verification",
        '$ErrorActionPreference = "Continue"',
        f'$logFile = "{workspace_dir}\\\\{log_file}"',
        f'$caseId = "{test_case_id}"',
        "",
        "# Initialize log file",
        'function Write-Log {',
        '    param([string]$Message, [string]$Color = "White")',
        '    Write-Host $Message -ForegroundColor $Color',
        '    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"',
        '    "[$timestamp] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8',
        '}',
        "",
        '"="*80 | Out-File -FilePath $logFile -Encoding UTF8',
        '"Test Execution Log" | Out-File -FilePath $logFile -Append -Encoding UTF8',
        '"Test Case: " + $caseId | Out-File -FilePath $logFile -Append -Encoding UTF8',
        '"Started: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $logFile -Append -Encoding UTF8',
        '"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8',
        '""  | Out-File -FilePath $logFile -Append -Encoding UTF8',
        "",
        'Write-Log ("="*80) Cyan',
        'Write-Log "Test Execution Started" Cyan',
        'Write-Log ("="*80) Cyan',
        'Write-Log ""',
        "",
        "$script:results = @()",
        ""
    ]
    
    for step in steps:
        step_num = step['step']
        action = step['action'][:60].replace('"', "'").replace('\n', ' ').replace('\r', ' ')
        action_script = step.get('action_script', '').strip()
        verify_script = step.get('verify_script', '').strip() if step.get('verify_script') else ''
        need_manual = step.get('need_vision_verify', False)
        
        lines.append(f"# {'='*70}")
        lines.append(f"# Step {step_num}: {action}")
        lines.append(f"# {'='*70}")
        lines.append('Write-Log ("-"*60) Gray')
        lines.append(f'Write-Log "Step {step_num}: {action}..." Cyan')
        lines.append('Write-Log ("-"*60) Gray')
        lines.append("")
        
        # Action script
        if action_script and not action_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Log "Executing Action..." Yellow')
            lines.append("try {")
            lines.append(f"    {action_script}")
            lines.append('    Write-Log "    [OK] Action executed" Green')
            lines.append(f'    $script:results += @{{Step={step_num}; Action="Success"}}')
            lines.append("} catch {")
            lines.append('    Write-Log "    [FAIL] Action failed: $($_.Exception.Message)" Red')
            lines.append(f'    $script:results += @{{Step={step_num}; Action="Failed"}}')
            lines.append("}")
            lines.append("")
            
            # Wait for operations to stabilize
            if 'start-process' in action_script.lower() or 'msiexec' in action_script.lower():
                lines.append("Start-Sleep -Seconds 2")
                lines.append("")
        elif action_script and action_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Log "Action: Manual operation required" Yellow')
            lines.append("")
        else:
            lines.append('Write-Log "Action: (Empty - verification only)" Gray')
            lines.append("")
        
        # Manual verification for need_vision_verify steps
        if need_manual:
            lines.append("# Manual Verification")
            lines.append('Write-Host ""')
            lines.append('Write-Host ("="*60) -ForegroundColor Yellow')
            lines.append(f'Write-Host "Step {step_num}: Manual Verification Required" -ForegroundColor Yellow')
            lines.append('Write-Host ("="*60) -ForegroundColor Yellow')
            lines.append('Write-Host "Please check the result manually and choose:" -ForegroundColor Yellow')
            lines.append('Write-Host "  [1] Success - Continue to next step" -ForegroundColor Green')
            lines.append('Write-Host "  [2] Failed - Mark as failed and continue" -ForegroundColor Red')
            lines.append('Write-Host ""')
            lines.append('do {')
            lines.append('    $choice = Read-Host "Enter your choice (1 or 2)"')
            lines.append('    if ($choice -eq "1") {')
            lines.append('        Write-Log "    [✓] Manual verification: Success" Green')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Success (Manual)"}}')
            lines.append('        break')
            lines.append('    } elseif ($choice -eq "2") {')
            lines.append('        Write-Log "    [✗] Manual verification: Failed" Red')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Failed (Manual)"}}')
            lines.append('        break')
            lines.append('    } else {')
            lines.append('        Write-Host "Invalid choice. Please enter 1 or 2." -ForegroundColor Red')
            lines.append('    }')
            lines.append('} while ($true)')
            lines.append('Write-Host ""')
            lines.append("")
        # Regular verify script
        elif verify_script and not verify_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Log "Verifying..." Yellow')
            lines.append("try {")
            modified_verify = verify_script.replace('exit 0', '$verifyExitCode=0').replace('exit 1', '$verifyExitCode=1')
            lines.append("    $verifyExitCode=1")
            lines.append(f"    {modified_verify}")
            lines.append("    if ($verifyExitCode -eq 0) {")
            lines.append('        Write-Log "    [OK] Verification passed" Green')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Success"}}')
            lines.append("    } else {")
            lines.append('        Write-Log "    [FAIL] Verification failed (exit code: $verifyExitCode)" Red')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Failed"}}')
            lines.append("    }")
            lines.append("} catch {")
            lines.append('    Write-Log "    [ERROR] Verification exception: $($_.Exception.Message)" Red')
            lines.append(f'    $script:results += @{{Step={step_num}; Verify="Failed"}}')
            lines.append("}")
            lines.append("")
        elif verify_script and verify_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Log "Verification: Manual check required" Yellow')
            lines.append("")
        else:
            lines.append('Write-Log "Verification: (None)" Gray')
            lines.append("")
        
        lines.append("Start-Sleep -Milliseconds 300")
        lines.append("")
    
    # Summary
    lines.append("")
    lines.append('Write-Log "" White')
    lines.append('Write-Log ("="*80) Green')
    lines.append('Write-Log "Test Execution Completed - Summary" Green')
    lines.append('Write-Log ("="*80) Green')
    lines.append('Write-Log "" White')
    lines.append("")
    lines.append("# Display results table")
    lines.append('Write-Host ("="*80) -ForegroundColor Cyan')
    lines.append('Write-Host "Detailed Results:" -ForegroundColor Cyan')
    lines.append('Write-Host ("="*80) -ForegroundColor Cyan')
    lines.append('$script:results | Format-Table -AutoSize')
    lines.append("")
    lines.append("# Write detailed results to log")
    lines.append('"" | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append('"Detailed Results:" | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append('"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append('$script:results | Format-Table -AutoSize | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append("")
    lines.append("# Summary counts")
    lines.append('$successCount = ($script:results | Where-Object { $_.Action -eq "Success" -or $_.Verify -match "Success" }).Count')
    lines.append('$failedCount = ($script:results | Where-Object { $_.Action -eq "Failed" -or $_.Verify -match "Failed" }).Count')
    lines.append('Write-Log "Success: $successCount" Green')
    lines.append('Write-Log "Failed: $failedCount" Red')
    lines.append('Write-Log "" White')
    lines.append('Write-Log "Log file: $logFile" Cyan')
    lines.append('Write-Log "" White')
    lines.append('"" | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append('"Test completed at: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append('"="*80 | Out-File -FilePath $logFile -Append -Encoding UTF8')
    lines.append("")
    lines.append('Write-Host "Press Enter to close" -ForegroundColor Yellow')
    lines.append("pause")
    
    return "\n".join(lines)

def main():
    # Load test case
    test_file = 'outputs/34714753.optimized.json'
    
    print(f"\n{'='*80}")
    print(f"🧪 测试用例: {test_file}")
    print(f"🎯 执行模式: 单会话 + 手动验证 + 日志记录")
    print(f"⚠️  只会弹出一次 UAC 窗口")
    print(f"{'='*80}\n")
    
    with open(test_file, 'r', encoding='utf-8') as f:
        test_case = json.load(f)
    
    steps = test_case['steps']
    test_case_id = test_case.get('test_case_id', '').replace('testcase-', '')
    
    # Generate log file name with timestamp
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_file = f"outputs/test_execution_{timestamp}.log"
    
    print(f"📋 总步骤数: {len(steps)}")
    manual_steps = [s for s in steps if s.get('need_vision_verify', False)]
    print(f"👁️  需要手动验证的步骤: {len(manual_steps)} (Steps: {[s['step'] for s in manual_steps]})")
    print(f"📄 日志文件: {log_file}")
    print()
    
    # Generate script
    script_content = generate_script_with_manual_verify(steps, test_case_id, log_file)
    
    # Save to file
    script_path = Path("outputs/test_with_manual_verify.ps1")
    script_path.write_text(script_content, encoding='utf-8-sig')
    
    print(f"📝 生成的脚本: {script_path.absolute()}")
    print()
    
    print(f"🚀 正在启动管理员 PowerShell 窗口...")
    print(f"   ⚠️  请在 UAC 窗口中点击'是'")
    print(f"   📺 所有输出将显示在 PowerShell 窗口中")
    print(f"   📄 执行日志将保存到: {log_file}")
    print()
    
    # Execute with admin privileges
    try:
        subprocess.Popen(
            [
                'powershell.exe',
                '-WindowStyle', 'Hidden',
                '-Command',
                f"Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','\"{script_path.absolute()}\"' -Verb RunAs -WindowStyle Normal"
            ],
            creationflags=subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS
        )
        
        print(f"✅ 已启动管理员 PowerShell 窗口")
        print(f"📺 请查看 PowerShell 窗口以查看执行进度")
        print(f"📄 执行完成后可以查看日志文件了解详情")
        print()
        
    except Exception as e:
        print(f"❌ 启动失败: {e}")
        return False
    
    print(f"{'='*80}")
    print(f"ℹ️  执行说明:")
    print(f"   1. UAC 窗口弹出后，点击'是'")
    print(f"   2. 所有步骤在 PowerShell 窗口中执行")
    print(f"   3. 当执行到 Step 4 时:")
    print(f"      - 会弹出安装完成对话框")
    print(f"      - 请手动检查对话框内容")
    print(f"      - 选择 [1] 成功 或 [2] 失败")
    print(f"      - 测试会继续执行")
    print(f"   4. 所有输出同时显示在窗口和日志文件中")
    print(f"   5. 执行完成后按 Enter 关闭窗口")
    print(f"   6. 查看日志文件: {log_file}")
    print(f"{'='*80}\n")

if __name__ == '__main__':
    main()
