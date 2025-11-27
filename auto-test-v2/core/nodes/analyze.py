"""
Analyze Node: AI analysis of test execution logs
分析节点：AI分析测试执行日志
"""
from ..state import AutoTestState
from ..report_generator import ReportGenerator


def analyze_logs_node(state: AutoTestState) -> AutoTestState:
    """
    Analyze test execution logs using AI
    
    Args:
        state: Current workflow state with test_logs
    
    Returns:
        Updated state with ai_analysis
    """
    try:
        test_logs = state.get("test_logs")
        
        if not test_logs:
            return {
                **state,
                "current_step": "analyze_logs",
                "errors": state["errors"] + ["No test logs available for analysis"]
            }
        
        # Use ReportGenerator's analyze_logs_with_ai method
        report_gen = ReportGenerator()
        ai_analysis = report_gen.analyze_logs_with_ai(
            logs=test_logs,
            test_case_id=state["test_case_id"]
        )
        
        return {
            **state,
            "current_step": "analyze_logs",
            "ai_analysis": ai_analysis
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "analyze_logs",
            "ai_analysis": f"⚠️ AI analysis failed: {str(e)}",
            "errors": state["errors"] + [f"AI analysis failed: {str(e)}"]
        }
