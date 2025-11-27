"""
Test script for AI Quality Evaluation feature
Verifies that ScriptEvaluator works correctly end-to-end
"""

from core.script_evaluator import ScriptEvaluator
from pathlib import Path

def test_basic_evaluation():
    """Test basic evaluation with a sample script"""
    
    print("=== Testing AI Quality Evaluation ===\n")
    
    # Sample PowerShell script for testing
    sample_script = """
# Test Script for Demo
param(
    [string]$TestParam = "default"
)

# Set error handling
$ErrorActionPreference = "Stop"

# Initialize log file
$LogFile = "test_log.txt"
"[INFO] Starting test at $(Get-Date)" | Out-File $LogFile

try {
    # Step 1: Check if service exists
    Write-Host "[INFO] Checking service..."
    $service = Get-Service -Name "SomeService" -ErrorAction SilentlyContinue
    
    if ($service) {
        Write-Host "[PASS] Service found"
        "[PASS] Service found" | Out-File $LogFile -Append
    } else {
        Write-Host "[FAIL] Service not found"
        "[FAIL] Service not found" | Out-File $LogFile -Append
        exit 1
    }
    
    # Step 2: Test network connectivity
    Write-Host "[INFO] Testing network..."
    $ping = Test-Connection -ComputerName "localhost" -Count 1 -Quiet
    
    if ($ping) {
        Write-Host "[PASS] Network test successful"
        "[PASS] Network test successful" | Out-File $LogFile -Append
    } else {
        Write-Host "[FAIL] Network test failed"
        "[FAIL] Network test failed" | Out-File $LogFile -Append
        exit 1
    }
    
    # Final result
    Write-Host "[PASS] All tests completed successfully"
    "[PASS] All tests completed successfully" | Out-File $LogFile -Append
    exit 0
    
} catch {
    Write-Host "[ERROR] Exception: $($_.Exception.Message)"
    "[ERROR] Exception: $($_.Exception.Message)" | Out-File $LogFile -Append
    exit 1
}
"""
    
    # Test case metadata
    test_case = {
        "test_case_id": "DEMO-001",
        "description": "Test service and network connectivity",
        "steps": [
            "Check if SomeService exists",
            "Test network connectivity to localhost",
            "Verify all tests pass"
        ]
    }
    
    print("📝 Sample Script:")
    print("-" * 60)
    print(sample_script[:200] + "...")
    print("-" * 60)
    print()
    
    print("🔧 Initializing ScriptEvaluator...")
    evaluator = ScriptEvaluator()
    
    print("🤖 Evaluating script quality with AI...")
    print("   (This may take 10-30 seconds depending on API response time)")
    print()
    
    try:
        result = evaluator.evaluate_script_quality(
            script_content=sample_script,
            test_case=test_case
        )
        
        if result:
            print("✅ Evaluation completed successfully!\n")
            print("=" * 60)
            print(evaluator.format_evaluation_report(result))
            print("=" * 60)
            print()
            
            # Verify structure
            print("📊 Result Structure Verification:")
            assert "overall_score" in result, "Missing overall_score"
            assert "grade" in result, "Missing grade"
            assert "scores" in result, "Missing scores"
            assert "strengths" in result, "Missing strengths"
            assert "weaknesses" in result, "Missing weaknesses"
            
            print(f"   ✓ overall_score: {result['overall_score']}")
            print(f"   ✓ grade: {result['grade']}")
            print(f"   ✓ scores: {len(result['scores'])} dimensions")
            print(f"   ✓ strengths: {len(result['strengths'])} items")
            print(f"   ✓ weaknesses: {len(result['weaknesses'])} items")
            
            if "recommendations" in result:
                print(f"   ✓ recommendations: {len(result['recommendations'])} items")
            
            print("\n🎉 All tests passed!")
            return True
            
        else:
            print("❌ Evaluation returned None")
            return False
            
    except Exception as e:
        print(f"❌ Evaluation failed with error: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def test_poor_quality_script():
    """Test evaluation with a poorly written script"""
    
    print("\n=== Testing with Poor Quality Script ===\n")
    
    poor_script = """
# Bad script - no error handling, hardcoded paths, no logging
Get-Service someservice
echo "done"
"""
    
    test_case = {
        "test_case_id": "BAD-001",
        "description": "Test with minimal functionality",
        "steps": ["Check service"]
    }
    
    evaluator = ScriptEvaluator()
    result = evaluator.evaluate_script_quality(poor_script, test_case)
    
    if result:
        print(f"📊 Poor Script Score: {result['overall_score']}/100 (Grade: {result['grade']})")
        print(f"   Expected: Lower score than well-written script")
        print(f"   Weaknesses identified: {len(result['weaknesses'])}")
        return True
    return False


if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("🧪 AI Quality Evaluation Test Suite")
    print("=" * 60 + "\n")
    
    # Test 1: Basic evaluation
    success1 = test_basic_evaluation()
    
    # Test 2: Poor quality detection
    success2 = test_poor_quality_script()
    
    print("\n" + "=" * 60)
    if success1 and success2:
        print("✅ ALL TESTS PASSED")
    else:
        print("❌ SOME TESTS FAILED")
    print("=" * 60 + "\n")
