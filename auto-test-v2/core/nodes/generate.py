"""
Generate Node: Generate PowerShell test script using AI
生成节点：使用AI生成PowerShell测试脚本
"""
from pathlib import Path
from ..state import AutoTestState
from ..test_generator import TestScriptGenerator


def generate_script_node(state: AutoTestState) -> AutoTestState:
    """
    Generate PowerShell test script using AI
    
    Args:
        state: Current workflow state with parsed_data
    
    Returns:
        Updated state with generated_script_path and generated_script_content
    """
    try:
        # Check if we have parsed data
        if not state.get("parsed_data"):
            return {
                **state,
                "current_step": "generate_script",
                "errors": state["errors"] + ["No parsed data available for script generation"]
            }
        
        # Generate script
        generator = TestScriptGenerator()
        script_content = generator.generate_script(state["parsed_data"])
        
        # Save script to LangGraph-specific output directory
        output_dir = Path(__file__).parent.parent.parent / "output_langgraph"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Create logs subdirectory
        logs_dir = output_dir / "logs"
        logs_dir.mkdir(parents=True, exist_ok=True)
        
        # Replace log path in script to use LangGraph output directory
        # Original: $logDir = "$PSScriptRoot\\..\\output\\logs"
        # Replace with absolute path to output_langgraph/logs
        script_content = script_content.replace(
            '$logDir = "$PSScriptRoot\\..\\output\\logs"',
            f'$logDir = "{str(logs_dir)}"'
        )
        
        test_case_id = state["test_case_id"]
        script_filename = f"test_{test_case_id}.ps1"
        script_path = output_dir / script_filename
        
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(script_content)
        
        return {
            **state,
            "current_step": "generate_script",
            "generated_script_path": str(script_path),
            "generated_script_content": script_content
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "generate_script",
            "errors": state["errors"] + [f"Script generation failed: {str(e)}"]
        }
