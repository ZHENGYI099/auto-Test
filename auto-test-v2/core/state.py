"""
LangGraph State Definition for Auto-Test Workflow
定义自动化测试工作流的状态
"""
from typing import TypedDict, Optional, List, Dict, Any
from typing_extensions import Annotated


class AutoTestState(TypedDict):
    """
    Complete state for auto-test workflow
    包含整个测试工作流的所有状态信息
    """
    # ============ Input ============
    csv_path: str
    """Path to input CSV file"""
    
    test_case_id: str
    """Test case identifier (e.g., 'case1')"""
    
    # ============ Parsed Data ============
    parsed_data: Optional[Dict[str, Any]]
    """Parsed test case data from CSV"""
    
    # ============ Script Generation ============
    generated_script_path: Optional[str]
    """Path to generated PowerShell test script"""
    
    generated_script_content: Optional[str]
    """Content of generated script (for validation)"""
    
    # ============ Validation ============
    validation_issues: Optional[List[Dict[str, str]]]
    """List of validation issues found in script
    Format: [{"severity": "warning|critical", "message": "..."}]
    """
    
    validation_passed: Optional[bool]
    """Whether script passed validation"""
    
    # ============ Execution ============
    process_id: Optional[int]
    """PowerShell process ID"""
    
    execution_status: Optional[str]
    """Execution status: 'pending', 'running', 'completed', 'failed'"""
    
    log_file_path: Optional[str]
    """Path to PowerShell transcript log file"""
    
    test_logs: Optional[str]
    """Complete test execution logs"""
    
    # ============ Analysis ============
    ai_analysis: Optional[str]
    """AI-generated analysis of test logs"""
    
    # ============ Report ============
    report_path: Optional[str]
    """Path to generated HTML report"""
    
    # ============ Error Handling ============
    errors: List[str]
    """List of errors encountered during workflow"""
    
    retry_count: int
    """Number of retries attempted"""
    
    # ============ Metadata ============
    current_step: Optional[str]
    """Current workflow step name"""
    
    start_time: Optional[str]
    """Workflow start timestamp"""
    
    end_time: Optional[str]
    """Workflow end timestamp"""


# Default initial state
def create_initial_state(csv_path: str, test_case_id: str = "") -> AutoTestState:
    """
    Create initial state for workflow
    
    Args:
        csv_path: Path to CSV input file
        test_case_id: Optional test case ID (will be extracted from CSV if not provided)
    
    Returns:
        Initial AutoTestState
    """
    from datetime import datetime
    
    return AutoTestState(
        # Input
        csv_path=csv_path,
        test_case_id=test_case_id,
        
        # Intermediate results
        parsed_data=None,
        generated_script_path=None,
        generated_script_content=None,
        validation_issues=None,
        validation_passed=None,
        
        # Execution
        process_id=None,
        execution_status="pending",
        log_file_path=None,
        test_logs=None,
        
        # Output
        ai_analysis=None,
        report_path=None,
        
        # Error handling
        errors=[],
        retry_count=0,
        
        # Metadata
        current_step="initialized",
        start_time=datetime.now().isoformat(),
        end_time=None
    )
