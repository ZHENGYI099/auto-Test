"""
Parse Node: Parse CSV file and extract test case data
解析节点：解析CSV文件并提取测试用例数据
"""
from pathlib import Path
from ..state import AutoTestState
from ..csv_parser import parse_csv_to_json


def parse_csv_node(state: AutoTestState) -> AutoTestState:
    """
    Parse CSV file and extract test case data
    
    Args:
        state: Current workflow state
    
    Returns:
        Updated state with parsed_data
    """
    csv_path = state["csv_path"]
    
    try:
        # Validate CSV file exists
        if not Path(csv_path).exists():
            return {
                **state,
                "current_step": "parse_csv",
                "errors": state["errors"] + [f"CSV file not found: {csv_path}"]
            }
        
        # Parse CSV
        parsed_data = parse_csv_to_json(csv_path)
        
        # Extract test case ID if not provided
        test_case_id = state["test_case_id"]
        if not test_case_id and parsed_data:
            # Try to extract from parsed data or filename
            test_case_id = parsed_data.get("test_case_id") or Path(csv_path).stem.replace("test", "").replace("_", "")
        
        return {
            **state,
            "current_step": "parse_csv",
            "parsed_data": parsed_data,
            "test_case_id": test_case_id or "unknown"
        }
        
    except Exception as e:
        return {
            **state,
            "current_step": "parse_csv",
            "errors": state["errors"] + [f"CSV parsing failed: {str(e)}"]
        }
