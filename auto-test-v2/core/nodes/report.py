"""
Report Node: Generate HTML test report
报告节点：生成HTML测试报告
"""
from datetime import datetime
from pathlib import Path
from ..state import AutoTestState
from ..report_generator import ReportGenerator


def generate_report_node(state: AutoTestState) -> AutoTestState:
    """
    Generate HTML report with test results and AI analysis
    
    Args:
        state: Current workflow state with all results
    
    Returns:
        Updated state with report_path and end_time
    """
    try:
        # Format validation report
        validation_report = ""
        if state.get("validation_issues"):
            issues = state["validation_issues"]
            if issues:
                validation_report = "\n".join([
                    f"[{issue['severity'].upper()}] {issue['message']}"
                    for issue in issues
                ])
        
        # Generate report using ReportGenerator
        report_gen = ReportGenerator()
        
        # Temporarily generate to default location
        temp_report_path = report_gen.generate_html_report(
            test_case_id=state["test_case_id"],
            script_path=state.get("generated_script_path", ""),
            logs=state.get("test_logs", ""),
            ai_analysis=state.get("ai_analysis", ""),
            timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            validation_report=validation_report
        )
        
        # Move report to LangGraph-specific directory
        langgraph_report_dir = Path(__file__).parent.parent.parent / "output_langgraph" / "reports"
        langgraph_report_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy to LangGraph directory
        import shutil
        report_filename = Path(temp_report_path).name
        final_report_path = langgraph_report_dir / report_filename
        shutil.copy2(temp_report_path, final_report_path)
        
        # Remove temp file
        Path(temp_report_path).unlink()
        
        return {
            **state,
            "current_step": "generate_report",
            "report_path": str(final_report_path),
            "end_time": datetime.now().isoformat()
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "generate_report",
            "errors": state["errors"] + [f"Report generation failed: {str(e)}"],
            "end_time": datetime.now().isoformat()
        }
