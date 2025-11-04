"""
Test Executor - Execute all steps in ONE admin PowerShell session
Only ONE UAC prompt at the beginning
"""
import json
import subprocess
import time
from pathlib import Path

def generate_single_script(steps):
    """Generate a single PowerShell script that executes all steps"""
    
    lines = [
        "# Test Execution Script - All steps in one session",
        '$ErrorActionPreference = "Continue"',
        "",
        'Write-Host ("="*80) -ForegroundColor Cyan',
        'Write-Host "Test Execution Started" -ForegroundColor Cyan',
        'Write-Host ("="*80) -ForegroundColor Cyan',
        "Write-Host ''",
        ""
    ]
    
    results_var = "$script:results = @()"
    lines.append(results_var)
    lines.append("")
    
    for step in steps:
        step_num = step['step']
        # Replace double quotes and remove newlines to avoid syntax errors
        action = step['action'][:60].replace('"', "'").replace('\n', ' ').replace('\r', ' ')
        action_script = step.get('action_script', '').strip()
        verify_script = step.get('verify_script', '').strip() if step.get('verify_script') else ''
        
        lines.append(f"# {'='*70}")
        lines.append(f"# Step {step_num}: {action}")
        lines.append(f"# {'='*70}")
        lines.append("")
        lines.append('Write-Host ("-"*60) -ForegroundColor Gray')
        lines.append(f'Write-Host "Step {step_num}: {action}..." -ForegroundColor Cyan')
        lines.append('Write-Host ("-"*60) -ForegroundColor Gray')
        lines.append("")
        
        # Action script
        if action_script and not action_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Host "Executing Action..." -ForegroundColor Yellow')
            lines.append("try {")
            lines.append(f"    {action_script}")
            lines.append('    Write-Host "    [OK] Action succeeded" -ForegroundColor Green')
            lines.append(f'    $script:results += @{{Step={step_num}; Action="Success"}}')
            lines.append("} catch {")
            lines.append('    Write-Host "    [FAIL] Action failed: " -NoNewline -ForegroundColor Red')
            lines.append("    Write-Host $_.Exception.Message -ForegroundColor Red")
            lines.append(f'    $script:results += @{{Step={step_num}; Action="Failed"}}')
            lines.append("}")
            lines.append("")
            # Wait for operations to stabilize
            if 'start-process' in action_script.lower() or 'explorer' in action_script.lower():
                lines.append("Start-Sleep -Seconds 2")
                lines.append("")
        elif action_script and action_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Host "Action: Manual operation required" -ForegroundColor Yellow')
            lines.append("")
        else:
            lines.append('Write-Host "Action: (Empty - verification only)" -ForegroundColor Gray')
            lines.append("")
        
        # Verify script
        if verify_script and not verify_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Host "Verifying..." -ForegroundColor Yellow')
            lines.append("try {")
            # Execute verify script directly in the current admin session (not in a subprocess)
            # Replace 'exit 0/1' with setting a variable instead
            modified_verify = verify_script.replace('exit 0', '$verifyExitCode=0').replace('exit 1', '$verifyExitCode=1')
            lines.append(f"    $verifyExitCode=1")
            lines.append(f"    {modified_verify}")
            lines.append("    if ($verifyExitCode -eq 0) {")
            lines.append('        Write-Host "    [OK] Verification passed" -ForegroundColor Green')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Success"}}')
            lines.append("    } else {")
            lines.append('        Write-Host "    [FAIL] Verification failed (exit code: " -NoNewline -ForegroundColor Red')
            lines.append("        Write-Host $verifyExitCode -NoNewline -ForegroundColor Red")
            lines.append('        Write-Host ")" -ForegroundColor Red')
            lines.append(f'        $script:results += @{{Step={step_num}; Verify="Failed"}}')
            lines.append("    }")
            lines.append("} catch {")
            lines.append('    Write-Host "    [ERROR] Verification exception: " -NoNewline -ForegroundColor Red')
            lines.append("    Write-Host $_.Exception.Message -ForegroundColor Red")
            lines.append(f'    $script:results += @{{Step={step_num}; Verify="Failed"}}')
            lines.append("}")
            lines.append("")
        elif verify_script and verify_script.lower().startswith("throw 'manual_check"):
            lines.append('Write-Host "Verification: Manual check required" -ForegroundColor Yellow')
            lines.append("")
        else:
            lines.append('Write-Host "Verification: (None)" -ForegroundColor Gray')
            lines.append("")
        
        lines.append("Start-Sleep -Milliseconds 300")
        lines.append("")
    
    # Summary
    lines.append("")
    lines.append("Write-Host ''")
    lines.append('Write-Host ("="*80) -ForegroundColor Green')
    lines.append('Write-Host "Test Execution Completed - Summary" -ForegroundColor Green')
    lines.append('Write-Host ("="*80) -ForegroundColor Green')
    lines.append("Write-Host ''")
    lines.append('$successCount = ($script:results | Where-Object { $_.Action -eq "Success" -or $_.Verify -eq "Success" }).Count')
    lines.append('$failedCount = ($script:results | Where-Object { $_.Action -eq "Failed" -or $_.Verify -eq "Failed" }).Count')
    lines.append('Write-Host "Success: " -NoNewline -ForegroundColor Green')
    lines.append("Write-Host $successCount -ForegroundColor Green")
    lines.append('Write-Host "Failed: " -NoNewline -ForegroundColor Red')
    lines.append("Write-Host $failedCount -ForegroundColor Red")
    lines.append("Write-Host ''")
    lines.append('Write-Host "Press Enter to close" -ForegroundColor Yellow')
    lines.append("pause")
    
    return "\n".join(lines)

def main():
    # Load test case
    test_file = 'outputs/34714753.optimized.json'
    
    print(f"\n{'='*80}")
    print(f"🧪 测试用例: {test_file}")
    print(f"🎯 执行模式: 所有步骤在一个管理员 PowerShell 会话中执行")
    print(f"⚠️  只会弹出一次 UAC 窗口")
    print(f"{'='*80}\n")
    
    with open(test_file, 'r', encoding='utf-8') as f:
        test_case = json.load(f)
    
    steps = test_case['steps']
    
    print(f"📋 总步骤数: {len(steps)}")
    print(f"⚙️  Action 步骤: {sum(1 for s in steps if s.get('action_script', '').strip())}")
    print(f"🔬 Verify 步骤: {sum(1 for s in steps if (s.get('verify_script') or '').strip())}")
    print()
    
    # Generate script
    script_content = generate_single_script(steps)
    
    # Save to file with UTF-8 BOM to ensure proper encoding
    script_path = Path("outputs/test_all_steps.ps1")
    script_path.write_text(script_content, encoding='utf-8-sig')
    
    print(f"📝 生成的脚本: {script_path.absolute()}")
    print()
    print(f"🚀 正在启动管理员 PowerShell 窗口...")
    print(f"   ⚠️  请在 UAC 窗口中点击'是'")
    print(f"   ⚠️  PowerShell 窗口会保持打开，显示所有执行结果")
    print()
    
    # Execute with admin privileges in a visible window
    try:
        subprocess.run(
            [
                'powershell.exe',
                '-Command',
                f"Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','{script_path.absolute()}' -Verb RunAs"
            ],
            check=False
        )
        
        print(f"✅ 已启动管理员 PowerShell 窗口")
        print(f"📺 请查看弹出的 PowerShell 窗口以查看执行进度和结果")
        print()
        
    except Exception as e:
        print(f"❌ 启动失败: {e}")
        return False
    
    print(f"{'='*80}")
    print(f"ℹ️  执行说明:")
    print(f"   1. UAC 窗口弹出后，点击'是'")
    print(f"   2. 管理员 PowerShell 窗口会打开并自动执行所有步骤")
    print(f"   3. 执行完成后会显示汇总结果")
    print(f"   4. 按任意键可关闭窗口")
    print(f"{'='*80}\n")

if __name__ == '__main__':
    main()
