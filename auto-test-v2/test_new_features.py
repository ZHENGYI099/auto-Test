# 测试新功能
# 1. 脚本验证
# 2. HTML报告生成
# 3. AI分析

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from core.script_validator import ScriptValidator
from core.report_generator import ReportGenerator

def test_script_validator():
    """测试脚本验证器"""
    print("\n" + "="*60)
    print("测试脚本验证器")
    print("="*60)
    
    # 测试一个有问题的脚本
    bad_script = """
    # 这个脚本有问题
    $service = Get-Service -Name "MyService"
    if ($service.Status.Trim() -eq "Running") {
        Write-Host "Running"
    }
    
    # 使用了 /qn+ (不完全静默)
    msiexec /i test.msi /qn+
    
    # 没有 Start-Transcript
    # 没有 try-catch
    """
    
    validator = ScriptValidator()
    result = validator.validate_script(bad_script)
    
    print(f"\n验证结果:")
    print(f"  是否有效: {result['is_valid']}")
    print(f"  错误数: {result['issue_count']}")
    print(f"  警告数: {result['warning_count']}")
    
    print(f"\n详细报告:")
    print(validator.get_validation_report())
    
    # 测试一个好的脚本
    print("\n" + "-"*60)
    good_script = """
    Start-Transcript -Path "test.log"
    
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "需要管理员权限"
        exit 1
    }
    
    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "test.msi", "/qn" -Wait -PassThru
        $exitCode = $process.ExitCode
        
        if ($exitCode -eq 0) {
            Write-Host "[PASS] 安装成功"
        } else {
            Write-Host "[FAIL] 安装失败: $exitCode"
        }
    } catch {
        Write-Host "[FAIL] 异常: $_"
    }
    
    Write-Host "TEST EXECUTION SUMMARY"
    Stop-Transcript
    """
    
    result2 = validator.validate_script(good_script)
    print(f"\n好脚本验证结果:")
    print(f"  是否有效: {result2['is_valid']}")
    print(f"  错误数: {result2['issue_count']}")
    print(f"  警告数: {result2['warning_count']}")
    print(f"\n{validator.get_validation_report()}")


def test_report_generator():
    """测试报告生成器"""
    print("\n" + "="*60)
    print("测试HTML报告生成器")
    print("="*60)
    
    # 模拟测试日志
    sample_logs = """
============================================================
TEST EXECUTION START: 2025-11-19 10:30:00
============================================================

Checking prerequisites...
[PASS] Running as Administrator
[PASS] MSI file found at C:\\VMShare\\cmdextension.msi
[PASS] Product not installed (ready for test)

============================================================
PHASE 2: INSTALLATION
============================================================

Installing MSI...
[PASS] MSI installation succeeded (exit code 0)

============================================================
PHASE 3: VERIFICATION
============================================================

[PASS] Service 'CloudManagedDesktopExtension' is running
[PASS] Product present in installed programs
[FAIL] Log file not found at expected location
[WARN] WMI namespace check returned warning

============================================================
TEST EXECUTION SUMMARY
============================================================
Total Passed: 5
Total Failed: 1
"""
    
    try:
        generator = ReportGenerator()
        
        print("\n正在生成 AI 分析...")
        ai_analysis = generator.analyze_logs_with_ai(
            logs=sample_logs,
            test_case_id="test_case_demo"
        )
        
        print(f"\nAI 分析结果:")
        print("-" * 60)
        print(ai_analysis)
        print("-" * 60)
        
        print("\n正在生成 HTML 报告...")
        report_path = generator.generate_html_report(
            test_case_id="test_case_demo",
            script_path="output/test_demo.ps1",
            logs=sample_logs,
            ai_analysis=ai_analysis,
            validation_report="✓ 脚本已通过验证检查"
        )
        
        print(f"\n✅ HTML 报告已生成:")
        print(f"   路径: {report_path}")
        print(f"\n可以在浏览器中打开查看!")
        
        # 自动打开报告
        import webbrowser
        webbrowser.open(f"file:///{report_path}")
        
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    print("\n🧪 Auto-Test V2 - 功能测试")
    
    # 测试脚本验证器
    test_script_validator()
    
    # 测试报告生成器
    test_report_generator()
    
    print("\n✅ 所有测试完成!")
