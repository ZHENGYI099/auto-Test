"""
CSV to JSON Converter
将CSV测试用例转换为JSON格式
"""
import csv
import json
from pathlib import Path
from typing import List, Dict

def parse_csv_to_json(csv_path: str) -> Dict:
    """
    Parse CSV file to JSON format with optional test scenario support
    
    CSV格式:
    # Test Scenario: Check agent registration success...
    Step,Action,Expected
    1,Apply to all devices.,
    2,Press "Win + E" keys...,
    
    JSON格式:
    {
        "test_case_id": "case_name",
        "test_scenario": "Check agent registration success...",
        "steps": [
            {"step": 1, "action": "...", "expected": "..."}
        ]
    }
    """
    csv_file = Path(csv_path)
    
    # Extract test case ID from filename (e.g., "case1test.csv" -> "case1test")
    test_case_id = csv_file.stem
    
    # Extract test scenario from first line if it's a comment
    test_scenario = ""
    steps = []
    
    with open(csv_path, 'r', encoding='utf-8-sig') as f:
        # Check first line for scenario
        first_line = f.readline().strip()
        if first_line.startswith('#') or first_line.startswith('//'):
            # Extract scenario description
            test_scenario = first_line.lstrip('#/').strip()
            if test_scenario.lower().startswith('test scenario:'):
                test_scenario = test_scenario[14:].strip()  # Remove "Test Scenario:" prefix
        else:
            # Reset to start if no comment
            f.seek(0)
        
        reader = csv.DictReader(f)
        
        for row in reader:
            # Support multiple column name variations
            step_col = 'Steps' if 'Steps' in row else 'Step'
            expected_col = 'Expect result' if 'Expect result' in row else 'Expected'
            
            step_num = int(row[step_col]) if row[step_col].strip() else len(steps) + 1
            action = row['Action'].strip()
            expected = row[expected_col].strip() if expected_col in row else ''
            
            steps.append({
                'step': step_num,
                'action': action,
                'expected': expected
            })
    
    result = {
        'test_case_id': test_case_id,
        'test_scenario': test_scenario,  # Include test scenario
        'steps': steps
    }
    
    return result

def save_json(data: Dict, output_path: str):
    """Save JSON data to file"""
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def main():
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python csv_parser.py <csv_file> [output_json]")
        sys.exit(1)
    
    csv_path = sys.argv[1]
    
    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        # Auto-generate output path
        csv_file = Path(csv_path)
        output_path = f"input/{csv_file.stem}.json"
    
    print(f"📄 Reading CSV: {csv_path}")
    data = parse_csv_to_json(csv_path)
    
    print(f"✅ Parsed {len(data['steps'])} steps")
    print(f"💾 Saving to: {output_path}")
    
    save_json(data, output_path)
    print(f"✅ Done!")

if __name__ == '__main__':
    main()
