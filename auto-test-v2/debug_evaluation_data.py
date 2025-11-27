"""
Debug script to check evaluation data structure
"""

import json
from pathlib import Path

# Sample evaluation data as it should be
correct_format = {
    "overall_score": 72,
    "grade": "C",
    "scores": {
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

print("=" * 60)
print("Expected Evaluation Data Structure")
print("=" * 60)
print(json.dumps(correct_format, indent=2))
print()

# Verify weighted score calculation
scores = correct_format["scores"]
weights = {
    "correctness": 0.30,
    "completeness": 0.25,
    "best_practices": 0.15,
    "robustness": 0.20,
    "maintainability": 0.10
}

calculated_score = (
    scores["correctness"] * weights["correctness"] +
    scores["completeness"] * weights["completeness"] +
    scores["best_practices"] * weights["best_practices"] +
    scores["robustness"] * weights["robustness"] +
    scores["maintainability"] * weights["maintainability"]
)

print("=" * 60)
print("Score Calculation Verification")
print("=" * 60)
print(f"Correctness:     {scores['correctness']} × 30% = {scores['correctness'] * 0.30:.1f}")
print(f"Completeness:    {scores['completeness']} × 25% = {scores['completeness'] * 0.25:.1f}")
print(f"Best Practices:  {scores['best_practices']} × 15% = {scores['best_practices'] * 0.15:.1f}")
print(f"Robustness:      {scores['robustness']} × 20% = {scores['robustness'] * 0.20:.1f}")
print(f"Maintainability: {scores['maintainability']} × 10% = {scores['maintainability'] * 0.10:.1f}")
print("-" * 60)
print(f"Calculated Overall Score: {calculated_score:.1f}")
print(f"Reported Overall Score:   {correct_format['overall_score']}")
print(f"Match: {'✅ YES' if abs(calculated_score - correct_format['overall_score']) < 1 else '❌ NO'}")
print()

# Check for dimension scores that are 0
print("=" * 60)
print("Dimension Score Validation")
print("=" * 60)
all_valid = True
for dimension, score in scores.items():
    status = "✅" if score > 0 else "❌"
    print(f"{status} {dimension}: {score}")
    if score == 0:
        all_valid = False
        
if all_valid:
    print("\n✅ All dimension scores are valid (> 0)")
else:
    print("\n❌ Some dimension scores are 0 - this indicates a data issue!")
print()

# HTML template test
print("=" * 60)
print("HTML Template Preview")
print("=" * 60)
html_preview = f"""
<div class="dimension-card">
    <div class="dimension-name">Correctness</div>
    <div class="dimension-score">{scores['correctness']}/100</div>
    <div class="dimension-weight">Weight: 30%</div>
</div>
"""
print(html_preview)
