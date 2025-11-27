"""
LangGraph Workflow Definition for Auto-Test
定义自动化测试的LangGraph工作流
"""
from langgraph.graph import StateGraph, END
from .state import AutoTestState
from .nodes.parse import parse_csv_node
from .nodes.generate import generate_script_node
from .nodes.validate import validate_script_node
from .nodes.execute import execute_test_node
from .nodes.wait import wait_for_completion_node
from .nodes.analyze import analyze_logs_node
from .nodes.report import generate_report_node


def should_continue_after_parse(state: AutoTestState) -> str:
    """
    Decide whether to continue after CSV parsing
    
    Args:
        state: Current workflow state
    
    Returns:
        "generate" if parsing succeeded, "end" if failed
    """
    if state.get("errors") and not state.get("parsed_data"):
        return "end"
    return "generate"


def should_continue_after_validation(state: AutoTestState) -> str:
    """
    Decide whether to continue after script validation
    
    Args:
        state: Current workflow state
    
    Returns:
        "execute" if validation passed or only warnings
        "end" if critical errors found
    """
    # If validation explicitly failed, abort
    if state.get("validation_passed") is False:
        return "end"
    
    # Check for critical issues
    issues = state.get("validation_issues", [])
    has_critical = any(i.get("severity") == "critical" for i in issues)
    
    if has_critical:
        return "end"
    
    return "execute"


def should_retry_execution(state: AutoTestState) -> str:
    """
    Decide whether to retry execution or continue to analysis
    
    Args:
        state: Current workflow state
    
    Returns:
        "analyze" if completed successfully
        "retry" if failed and retries remaining
        "end" if failed with no retries left
    """
    execution_status = state.get("execution_status")
    
    if execution_status == "completed":
        return "analyze"
    
    if execution_status == "failed":
        retry_count = state.get("retry_count", 0)
        if retry_count < 3:
            return "retry"
        else:
            return "end"
    
    # Still running (shouldn't reach here normally)
    return "wait"


def create_workflow() -> StateGraph:
    """
    Create the auto-test workflow graph
    
    Returns:
        Compiled StateGraph ready to run
    """
    # Create graph
    workflow = StateGraph(AutoTestState)
    
    # Add nodes
    workflow.add_node("parse_csv", parse_csv_node)
    workflow.add_node("generate_script", generate_script_node)
    workflow.add_node("validate_script", validate_script_node)
    workflow.add_node("execute_test", execute_test_node)
    workflow.add_node("wait_completion", wait_for_completion_node)
    workflow.add_node("analyze_logs", analyze_logs_node)
    workflow.add_node("generate_report", generate_report_node)
    
    # Set entry point
    workflow.set_entry_point("parse_csv")
    
    # Define edges with conditional logic
    
    # After parsing, check if we should continue
    workflow.add_conditional_edges(
        "parse_csv",
        should_continue_after_parse,
        {
            "generate": "generate_script",
            "end": END
        }
    )
    
    # After generation, always validate
    workflow.add_edge("generate_script", "validate_script")
    
    # After validation, check if we should execute
    workflow.add_conditional_edges(
        "validate_script",
        should_continue_after_validation,
        {
            "execute": "execute_test",
            "end": END
        }
    )
    
    # After execution starts, wait for completion
    workflow.add_edge("execute_test", "wait_completion")
    
    # After waiting, check status and decide next step
    workflow.add_conditional_edges(
        "wait_completion",
        should_retry_execution,
        {
            "analyze": "analyze_logs",
            "retry": "execute_test",  # Loop back to retry
            "wait": "wait_completion",  # Loop back to wait more (edge case)
            "end": END
        }
    )
    
    # After analysis, generate report
    workflow.add_edge("analyze_logs", "generate_report")
    
    # After report generation, end
    workflow.add_edge("generate_report", END)
    
    # Compile graph
    return workflow.compile()


# Lazy initialization - create workflow only when needed
_auto_test_workflow = None

def get_workflow():
    """Get or create the auto-test workflow instance"""
    global _auto_test_workflow
    if _auto_test_workflow is None:
        print("🔧 Compiling LangGraph workflow...")
        _auto_test_workflow = create_workflow()
        print("✅ Workflow compiled")
    return _auto_test_workflow


def run_auto_test(csv_path: str, test_case_id: str = "") -> AutoTestState:
    """
    Run the complete auto-test workflow
    
    Args:
        csv_path: Path to CSV input file
        test_case_id: Optional test case ID
    
    Returns:
        Final workflow state
    """
    from .state import create_initial_state
    
    # Create initial state
    initial_state = create_initial_state(csv_path, test_case_id)
    
    # Get workflow instance
    workflow = get_workflow()
    
    # Run workflow
    final_state = workflow.invoke(initial_state)
    
    return final_state


def stream_auto_test(csv_path: str, test_case_id: str = ""):
    """
    Run auto-test workflow with streaming updates
    
    Args:
        csv_path: Path to CSV input file
        test_case_id: Optional test case ID
    
    Yields:
        State updates at each step
    """
    from .state import create_initial_state
    
    # Create initial state
    initial_state = create_initial_state(csv_path, test_case_id)
    
    # Get workflow instance
    workflow = get_workflow()
    
    # Stream workflow execution
    for state in workflow.stream(initial_state):
        yield state
