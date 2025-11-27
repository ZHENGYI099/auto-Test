"""
AI-Powered Script Quality Evaluator
使用 AI 评估自动生成脚本的质量
"""
import json
import re
from typing import Dict, Optional
from .model_client import ModelClient
from config.prompts import SCRIPT_EVALUATION_PROMPT


class ScriptEvaluator:
    """Evaluate auto-generated test script quality using AI"""
    
    def __init__(self, model_client: Optional[ModelClient] = None):
        """
        Initialize script evaluator
        
        Args:
            model_client: Optional ModelClient instance. If None, will create new one.
        """
        self.model_client = model_client or ModelClient()
    
    def evaluate_script_quality(
        self, 
        script: str, 
        test_case_id: str = "",
        test_scenario: str = "",
        expected_steps: int = 0
    ) -> Dict:
        """
        Evaluate script quality using AI
        
        Args:
            script: Generated PowerShell script
            test_case_id: Test case identifier
            test_scenario: Test scenario description
            expected_steps: Number of expected test steps
            
        Returns:
            Dict containing quality evaluation results:
            {
                "overall_score": 85,
                "grade": "A",
                "dimensions": {
                    "correctness": 90,
                    "completeness": 85,
                    "best_practices": 80,
                    "robustness": 90,
                    "maintainability": 75
                },
                "strengths": [...],
                "weaknesses": [...],
                "recommendations": [...]
            }
        """
        user_prompt = f"""Evaluate this auto-generated PowerShell test script:

TEST CASE ID: {test_case_id}
TEST SCENARIO: {test_scenario}
EXPECTED STEPS: {expected_steps}

SCRIPT TO EVALUATE:
```powershell
{script[:8000]}  # Limit to avoid token overflow
```

Provide a comprehensive quality evaluation in JSON format.
Calculate overall_score as weighted average:
- Correctness: 30%
- Completeness: 25%
- Best Practices: 15%
- Robustness: 20%
- Maintainability: 10%

Output ONLY valid JSON, no explanatory text."""

        try:
            print(" AI evaluating script quality...")
            
            # Call AI
            response = self.model_client.generate(
                system_prompt=SCRIPT_EVALUATION_PROMPT,
                user_prompt=user_prompt,
                temperature=0.3,  # Lower temperature for more consistent scoring
                max_tokens=2000
            )
            
            # Parse JSON response
            evaluation = self._parse_evaluation_response(response)
            
            # Add grade based on overall score
            evaluation["grade"] = self._calculate_grade(evaluation["overall_score"])
            
            print(f"✅ Evaluation complete: {evaluation['overall_score']}/100 ({evaluation['grade']})")
            
            return evaluation
            
        except Exception as e:
            print(f"⚠️ AI evaluation failed: {str(e)}")
            return self._get_fallback_evaluation()
    
    def _parse_evaluation_response(self, response: str) -> Dict:
        """
        Parse AI response and extract JSON evaluation
        
        Args:
            response: Raw AI response text
            
        Returns:
            Parsed evaluation dictionary
        """
        try:
            # Try to find JSON in response
            # Look for content between { and }
            json_match = re.search(r'\{[\s\S]*\}', response)
            if json_match:
                json_str = json_match.group(0)
                evaluation = json.loads(json_str)
                
                # Validate structure
                required_keys = ["overall_score", "dimensions", "strengths", "weaknesses", "recommendations"]
                if all(key in evaluation for key in required_keys):
                    # Convert "dimensions" to "scores" for compatibility with HTML template
                    evaluation["scores"] = evaluation.pop("dimensions")
                    return evaluation
            
            # If parsing failed, try direct JSON parse
            evaluation = json.loads(response)
            # Convert "dimensions" to "scores" if present
            if "dimensions" in evaluation:
                evaluation["scores"] = evaluation.pop("dimensions")
            return evaluation
            
        except json.JSONDecodeError as e:
            print(f"⚠️ Failed to parse AI response as JSON: {str(e)}")
            print(f"Response preview: {response[:200]}...")
            return self._get_fallback_evaluation()
    
    def _calculate_grade(self, score: int) -> str:
        """
        Convert numeric score to letter grade
        
        Args:
            score: Numeric score (0-100)
            
        Returns:
            Letter grade (A/B/C/D/F)
        """
        if score >= 90:
            return "A"
        elif score >= 80:
            return "B"
        elif score >= 70:
            return "C"
        elif score >= 60:
            return "D"
        else:
            return "F"
    
    def _get_fallback_evaluation(self) -> Dict:
        """
        Return fallback evaluation when AI fails
        
        Returns:
            Default evaluation dictionary
        """
        return {
            "overall_score": 0,
            "grade": "N/A",
            "scores": {
                "correctness": 0,
                "completeness": 0,
                "best_practices": 0,
                "robustness": 0,
                "maintainability": 0
            },
            "strengths": ["Unable to evaluate - AI analysis failed"],
            "weaknesses": ["Unable to evaluate - AI analysis failed"],
            "recommendations": ["Re-run evaluation or check AI service status"]
        }
    
    def format_evaluation_report(self, evaluation: Dict) -> str:
        """
        Format evaluation results as human-readable text
        
        Args:
            evaluation: Evaluation dictionary
            
        Returns:
            Formatted report string
        """
        report = []
        report.append("=" * 60)
        report.append("📊 SCRIPT QUALITY EVALUATION REPORT")
        report.append("=" * 60)
        report.append("")
        
        # Overall score
        report.append(f"Overall Score: {evaluation['overall_score']}/100 (Grade: {evaluation['grade']})")
        report.append("")
        
        # Dimension scores
        report.append("Dimension Scores:")
        report.append("-" * 40)
        scores = evaluation.get('scores', {})
        report.append(f"  Correctness:     {scores.get('correctness', 0):3d}/100")
        report.append(f"  Completeness:    {scores.get('completeness', 0):3d}/100")
        report.append(f"  Best Practices:  {scores.get('best_practices', 0):3d}/100")
        report.append(f"  Robustness:      {scores.get('robustness', 0):3d}/100")
        report.append(f"  Maintainability: {scores.get('maintainability', 0):3d}/100")
        report.append("")
        
        # Strengths
        report.append("✅ Strengths:")
        for i, strength in enumerate(evaluation.get('strengths', []), 1):
            report.append(f"  {i}. {strength}")
        report.append("")
        
        # Weaknesses
        report.append("⚠️ Weaknesses:")
        for i, weakness in enumerate(evaluation.get('weaknesses', []), 1):
            report.append(f"  {i}. {weakness}")
        report.append("")
        
        # Recommendations
        report.append("💡 Recommendations:")
        for i, rec in enumerate(evaluation.get('recommendations', []), 1):
            report.append(f"  {i}. {rec}")
        report.append("")
        
        report.append("=" * 60)
        
        return "\n".join(report)


if __name__ == "__main__":
    # Test the evaluator
    print("Testing ScriptEvaluator...")
    
    test_script = """
# Admin check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must run as Administrator"
    exit 1
}

# Phase 1: Pre-check
$msiPath = "C:\\VMShare\\cmdextension.msi"
if (-not (Test-Path $msiPath)) {
    Write-Host "[FAIL] MSI file not found"
    exit 1
}

# Phase 2: Installation
try {
    $exitCode = (Start-Process msiexec.exe -ArgumentList "/i","$msiPath","/qn" -Wait -PassThru).ExitCode
    Write-Host "[PASS] Installation exit code: $exitCode"
} catch {
    Write-Host "[FAIL] Installation failed: $_"
    exit 1
}

# Phase 3: Verification
$svc = Get-Service -Name "MyService" -ErrorAction SilentlyContinue
if ($svc.Status -eq "Running") {
    Write-Host "[PASS] Service is running"
} else {
    Write-Host "[FAIL] Service not running"
}
"""
    
    evaluator = ScriptEvaluator()
    result = evaluator.evaluate_script_quality(
        script=test_script,
        test_case_id="test_case_001",
        test_scenario="Install and verify service",
        expected_steps=5
    )
    
    print("\n" + evaluator.format_evaluation_report(result))
