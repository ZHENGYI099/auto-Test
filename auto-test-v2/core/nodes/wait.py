"""
Wait Node: Wait for test execution to complete
等待节点：等待测试执行完成
"""
import time
from pathlib import Path
from ..state import AutoTestState


def wait_for_completion_node(state: AutoTestState) -> AutoTestState:
    """
    Wait for PowerShell test script to complete by monitoring log file
    
    Args:
        state: Current workflow state with execution_status = "running"
    
    Returns:
        Updated state with test_logs and execution_status = "completed"
    """
    try:
        script_path = state.get("generated_script_path")
        
        if not script_path:
            return {
                **state,
                "current_step": "wait_completion",
                "errors": state["errors"] + ["No script path available"]
            }
        
        # Find log directory - LangGraph uses separate output folder
        script_dir = Path(script_path).parent
        log_dir = script_dir / "logs"
        
        # Create log directory if it doesn't exist
        log_dir.mkdir(parents=True, exist_ok=True)
        
        # Also check the test_case_id to match correct log file
        test_case_id = state.get("test_case_id", "")
        
        # Wait for log file to be created and completed
        max_wait = 300  # 5 minutes
        check_interval = 2  # 2 seconds
        elapsed = 0
        log_file_found = None
        
        while elapsed < max_wait:
            if log_dir.exists():
                # Get log files matching test case ID
                if test_case_id:
                    log_pattern = f"*{test_case_id}*.log"
                else:
                    log_pattern = "*.log"
                
                matching_logs = sorted(
                    log_dir.glob(log_pattern),
                    key=lambda p: p.stat().st_mtime,
                    reverse=True
                )
                
                if matching_logs:
                    log_file_found = matching_logs[0]
                    
                    # Check if log contains completion marker
                    try:
                        with open(log_file_found, 'r', encoding='utf-8') as f:
                            content = f.read()
                        
                        # Look for PowerShell transcript end marker
                        if ("Windows PowerShell 脚本结束" in content or 
                            (content.count("**********************") >= 2)):
                            # Script completed
                            break
                    except:
                        pass
            
            time.sleep(check_interval)
            elapsed += check_interval
        
        # Read final log content
        if log_file_found and log_file_found.exists():
            # Wait a bit more to ensure file is fully written
            time.sleep(2)
            
            with open(log_file_found, 'r', encoding='utf-8') as f:
                test_logs = f.read()
            
            return {
                **state,
                "current_step": "wait_completion",
                "log_file_path": str(log_file_found),
                "test_logs": test_logs,
                "execution_status": "completed"
            }
        else:
            return {
                **state,
                "current_step": "wait_completion",
                "execution_status": "failed",
                "errors": state["errors"] + [f"Timeout waiting for test completion ({max_wait}s)"]
            }
        
    except Exception as e:
        return {
            **state,
            "current_step": "wait_completion",
            "execution_status": "failed",
            "errors": state["errors"] + [f"Wait for completion failed: {str(e)}"]
        }
