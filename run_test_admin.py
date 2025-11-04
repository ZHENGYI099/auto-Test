"""
Simple and Direct Test Executor - Execute steps with admin privileges
Each step runs independently but with admin rights when needed
"""
import json
import subprocess
import time
from pathlib import Path

def execute_powershell_admin(script, step_info=""):
    """Execute a PowerShell script with admin privileges"""
    if not script or script.strip() == '':
        return {'success': True, 'output': '(Empty script - skipped)', 'exit_code': 0, 'skipped': True}
    
    # Handle manual check
    if script.strip().lower().startswith("throw 'manual_check"):
        return {'success': True, 'output': '(Manual check required)', 'exit_code': 0, 'manual': True}
    
    try:
        print(f"    Executing (with admin): {script[:80]}...")
        
        # Create a temporary script file (avoids quote escaping issues)
        temp_script = Path("outputs/temp_exec.ps1")
        temp_script.write_text(script, encoding='utf-8')
        
        # Execute with admin privileges using Start-Process -Verb RunAs -Wait
        wrapper_script = f"""
$result = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','{temp_script.absolute()}' -Verb RunAs -Wait -PassThru
exit $result.ExitCode
"""
        
        result = subprocess.run(
            ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', wrapper_script],
            capture_output=True,
            text=True,
            timeout=60,
            encoding='utf-8',
            errors='replace'
        )
        
        return {
            'success': result.returncode == 0,
            'output': result.stdout.strip() or result.stderr.strip() or '(No output)',
            'exit_code': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {'success': False, 'output': 'Timeout after 60 seconds', 'exit_code': -1}
    except Exception as e:
        return {'success': False, 'output': str(e), 'exit_code': -1}

def main():
    # Load test case
    test_file = 'outputs/34714753.optimized.json'
    print(f"\n{'='*80}")
    print(f"🧪 测试用例: {test_file}")
    print(f"⚡ 执行模式: 每个步骤独立执行（需要时自动提升权限）")
    print(f"{'='*80}\n")
    
    with open(test_file, 'r', encoding='utf-8') as f:
        test_case = json.load(f)
    
    steps = test_case['steps']
    results = []
    
    for step in steps:
        step_num = step['step']
        action = step['action']
        action_script = step.get('action_script', '').strip()
        verify_script = step.get('verify_script', '').strip() if step.get('verify_script') else ''
        
        print(f"\n{'─'*80}")
        print(f"📌 Step {step_num}: {action[:70]}...")
        print(f"{'─'*80}")
        
        step_result = {'step': step_num, 'action': action}
        
        # Execute action script
        if action_script:
            print(f"\n⚙️  Action Script:")
            result = execute_powershell_admin(action_script, f"Step {step_num} Action")
            
            if result.get('skipped'):
                print(f"    ⏭️  Skipped (empty)")
                step_result['action_status'] = 'skipped'
            elif result.get('manual'):
                print(f"    👁️  Manual operation required")
                step_result['action_status'] = 'manual'
            elif result['success']:
                print(f"    ✅ Success (exit code: {result['exit_code']})")
                if result['output'] and result['output'] != '(No output)':
                    print(f"    📤 Output: {result['output'][:200]}")
                step_result['action_status'] = 'success'
            else:
                print(f"    ❌ Failed (exit code: {result['exit_code']})")
                print(f"    ⚠️  Error: {result['output'][:200]}")
                step_result['action_status'] = 'failed'
            
            # Wait a bit for operations to complete
            time.sleep(1)
        else:
            print(f"\n⚙️  Action Script: (Empty - verification only)")
            step_result['action_status'] = 'empty'
        
        # Execute verify script
        if verify_script:
            print(f"\n🔬 Verify Script:")
            result = execute_powershell_admin(verify_script, f"Step {step_num} Verify")
            
            if result.get('manual'):
                print(f"    👁️  Manual verification required")
                step_result['verify_status'] = 'manual'
            elif result['success']:
                print(f"    ✅ Verification passed (exit code: {result['exit_code']})")
                if result['output'] and result['output'] != '(No output)':
                    print(f"    📤 Output: {result['output'][:200]}")
                step_result['verify_status'] = 'success'
            else:
                print(f"    ❌ Verification failed (exit code: {result['exit_code']})")
                print(f"    ⚠️  Reason: {result['output'][:200]}")
                step_result['verify_status'] = 'failed'
        else:
            print(f"\n🔬 Verify Script: (None)")
            step_result['verify_status'] = 'none'
        
        results.append(step_result)
        
        # Brief pause between steps
        time.sleep(0.5)
    
    # Summary
    print(f"\n{'='*80}")
    print(f"📊 执行结果汇总")
    print(f"{'='*80}\n")
    
    action_success = sum(1 for r in results if r.get('action_status') == 'success')
    action_failed = sum(1 for r in results if r.get('action_status') == 'failed')
    verify_success = sum(1 for r in results if r.get('verify_status') == 'success')
    verify_failed = sum(1 for r in results if r.get('verify_status') == 'failed')
    
    print(f"⚙️  Action Scripts: {action_success} ✅ / {action_failed} ❌")
    print(f"🔬 Verify Scripts: {verify_success} ✅ / {verify_failed} ❌")
    
    if action_failed == 0 and verify_failed == 0:
        print(f"\n🎉 所有步骤执行成功！")
    else:
        print(f"\n⚠️  部分步骤失败，请检查上面的详细输出")
    
    print(f"\n{'='*80}\n")

if __name__ == '__main__':
    main()
