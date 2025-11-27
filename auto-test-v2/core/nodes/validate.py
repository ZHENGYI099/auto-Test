"""
Validate Node: Validate generated PowerShell script
验证节点：验证生成的PowerShell脚本
"""
from ..state import AutoTestState
from ..script_validator import ScriptValidator


def validate_script_node(state: AutoTestState) -> AutoTestState:
    """
    Validate generated PowerShell script for common issues
    
    Args:
        state: Current workflow state with generated_script_content
    
    Returns:
        Updated state with validation_issues and validation_passed
    """
    try:
        # Check if we have script content
        if not state.get("generated_script_content"):
            return {
                **state,
                "current_step": "validate_script",
                "errors": state["errors"] + ["No script content available for validation"]
            }
        
        # Validate script
        validator = ScriptValidator()
        validation_result = validator.validate_script(state["generated_script_content"])
        
        # Extract issues
        issues = []
        for issue in validation_result.get("issues", []):
            issues.append({
                "severity": "critical",
                "message": issue
            })
        
        for warning in validation_result.get("warnings", []):
            issues.append({
                "severity": "warning",
                "message": warning
            })
        
        # Determine if validation passed
        # Pass if no critical issues
        has_critical = any(i["severity"] == "critical" for i in issues)
        validation_passed = not has_critical
        
        return {
            **state,
            "current_step": "validate_script",
            "validation_issues": issues,
            "validation_passed": validation_passed
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "validate_script",
            "errors": state["errors"] + [f"Script validation failed: {str(e)}"],
            "validation_passed": False
        }
