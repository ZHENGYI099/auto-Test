"""
Re-generate HTML report with corrected evaluation data
使用修正后的评估数据重新生成 HTML 报告
"""

from pathlib import Path
import sys

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from core.report_generator import ReportGenerator

# Corrected evaluation data (as it should be from AI)
corrected_evaluation = {
    "overall_score": 72,
    "grade": "C",
    "scores": {  # ✅ Changed from "dimensions" to "scores"
        "correctness": 75,
        "completeness": 70,
        "best_practices": 68,
        "robustness": 73,
        "maintainability": 72
    },
    "strengths": [
        "Good use of logging and transcript to capture test execution details.",
        "Includes error handling with try/catch and exit codes for major failure points.",
        "Functions are used for modularity (e.g., Write-Result, Get-InstalledProduct, Get-MSIProperty)."
    ],
    "weaknesses": [
        "Script is incomplete; verification steps are cut off and do not cover all 11 expected steps.",
        "Some best practices are inconsistently applied (e.g., use of script-scoped variables, inconsistent error messaging).",
        "Limited edge case handling (e.g., does not check for service recovery, log file content, or scheduled task existence)."
    ],
    "recommendations": [
        "Complete the verification phase to cover all 11 expected steps, including all verification points (e.g., log file existence, scheduled task, WMI namespace, etc.).",
        "Enhance error handling for all resource interactions (e.g., null checks after service queries, file existence, etc.).",
        "Improve maintainability by adding comments for each major step, using more descriptive variable names, and further modularizing repeated logic."
    ]
}

# Sample logs (simplified)
sample_logs = """[INFO] Starting test execution...
[PASS] Prerequisites check completed
[PASS] MSI installation completed
[PASS] Service installed: CloudManagedDesktopExtension
[FAIL] CloudManagedDesktopExtension - Startup Type is Automatic (Delayed Start)
  Expected: 'Delayed Auto'
  Actual: 'Auto'
[PASS] Log file exists: C:\\ProgramData\\CloudManagedDesktop\\Logs\\CloudManagedDesktop.log
[PASS] Scheduled task exists
[PASS] WMI namespace accessible
[PASS] Uninstallation completed successfully
[INFO] Test execution completed with 1 failure(s)"""

# Sample AI analysis
ai_analysis = """**1. Overall Test Result:**  
- **FAIL** (1 failed check out of 11 total)

**2. Key Findings and Observations:**  
- Prerequisites and MSI installation completed successfully.
- Most verification steps passed, confirming installation, service status, log presence, scheduled task, and WMI accessibility.
- Uninstallation process succeeded.

**3. Failed Checks with Probable Causes:**  
- **CloudManagedDesktopExtension - Startup Type is Automatic (Delayed Start):**
  - **Expected:** 'Delayed Auto'
  - **Actual:** 'Auto'
  - **Probable Cause:** The service was configured for standard automatic startup instead of 'Automatic (Delayed Start)'. This could be due to:
    - Incorrect MSI packaging or service configuration.
    - Missing or incorrect parameters in the installation script.
    - System policy or previous configuration overriding the startup type.

**4. Warnings or Potential Issues:**  
- Only one verification failed, but it may impact service startup timing and system performance.
- No other warnings or errors observed in the logs.

**5. Recommendations:**  
- **Review MSI/service configuration:** Ensure the service is set to 'Automatic (Delayed Start)' in the installer or configuration scripts.
- **Update installation script:** Explicitly set the startup type after installation using PowerShell (`Set-Service` or `sc.exe config`).
- **Re-test after correction:** Rerun the test case to confirm the startup type is as expected.
- **Document configuration:** Note the required startup type in deployment documentation to prevent future misconfiguration."""

def main():
    print("=" * 70)
    print("🔧 Re-generating HTML Report with Corrected Evaluation Data")
    print("=" * 70)
    print()
    
    # Initialize report generator
    report_gen = ReportGenerator()
    
    # Generate report with corrected data
    print("📝 Generating HTML report...")
    report_path = report_gen.generate_html_report(
        test_case_id="case1",
        script_path=str(Path("../output/test_case1.ps1").resolve()),
        logs=sample_logs,
        ai_analysis=ai_analysis,
        quality_evaluation=corrected_evaluation,  # ✅ Using corrected data
        timestamp="2025-11-26 19:38:37"
    )
    
    print(f"✅ Report generated successfully!")
    print(f"📄 Report path: {report_path}")
    print()
    
    # Verify dimension scores in report
    print("🔍 Verification:")
    print(f"   Overall Score: {corrected_evaluation['overall_score']}/100")
    print(f"   Grade: {corrected_evaluation['grade']}")
    print(f"   Dimension Scores:")
    for dim, score in corrected_evaluation['scores'].items():
        print(f"      • {dim}: {score}/100")
    print()
    
    print("💡 Next steps:")
    print("   1. Open the report in browser to verify all scores display correctly")
    print("   2. Check that dimension scores are no longer 0")
    print("   3. Future reports will use the fixed code automatically")
    print()
    print(f"🌐 Open: file:///{report_path.replace('\\\\', '/')}")

if __name__ == "__main__":
    main()
