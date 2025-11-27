"""
Execute Node: Execute PowerShell test script
执行节点：执行PowerShell测试脚本
"""
import subprocess
from pathlib import Path
from ..state import AutoTestState


def execute_test_node(state: AutoTestState) -> AutoTestState:
    """
    Execute PowerShell test script with admin privileges
    
    Args:
        state: Current workflow state with generated_script_path
    
    Returns:
        Updated state with process_id and execution_status
    """
    try:
        script_path = state.get("generated_script_path")
        
        if not script_path:
            return {
                **state,
                "current_step": "execute_test",
                "errors": state["errors"] + ["No script path available for execution"]
            }
        
        # Convert to absolute path
        abs_script_path = str(Path(script_path).resolve())
        
        # Escape path for PowerShell
        escaped_path = abs_script_path.replace('"', '`"')
        
        # Construct command to launch PowerShell as admin
        cmd_string = (
            f'Start-Process powershell -Verb RunAs '
            f'-ArgumentList "-NoProfile -ExecutionPolicy Bypass -File \\"{escaped_path}\\"" '
            f'-WindowStyle Normal'
        )
        
        cmd = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-Command",
            cmd_string
        ]
        
        # Start process
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            creationflags=subprocess.CREATE_NO_WINDOW
        )
        
        return {
            **state,
            "current_step": "execute_test",
            "process_id": process.pid,
            "execution_status": "running"
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "execute_test",
            "execution_status": "failed",
            "errors": state["errors"] + [f"Test execution failed: {str(e)}"]
        }
