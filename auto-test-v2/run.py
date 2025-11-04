"""

使用方法:
1. 准备 CSV 文件 (Step, Action, Expected 列)
2. python run.py --csv input/test.csv
   或
   python run.py --json input/test.json

CSV 会自动转换为 JSON，然后生成 PowerShell 测试脚本
"""
import argparse
import sys
from pathlib import Path

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from core.csv_parser import parse_csv_to_json, save_json
from core.test_generator import TestScriptGenerator

def main():
    parser = argparse.ArgumentParser(
        description='Generate goal-oriented PowerShell test scripts from CSV/JSON test cases'
    )
    
    # Input options
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('--csv', help='Input CSV file path')
    input_group.add_argument('--json', help='Input JSON file path')
    
    # Output options
    parser.add_argument('-o', '--output', help='Output PowerShell script path (optional, auto-generated if not provided)')
    parser.add_argument('--no-refine', action='store_true', help='Skip script refinement step')
    parser.add_argument('--keep-json', action='store_true', help='Keep intermediate JSON file (for CSV input)')
    
    args = parser.parse_args()
    
    print(f"\n{'='*70}")
    print(f"  Auto-Test V2 - Goal-Oriented Test Script Generator")
    print(f"{'='*70}\n")
    
    json_path = None
    temp_json = False
    
    # Step 1: Convert CSV to JSON if needed
    if args.csv:
        csv_file = Path(args.csv)
        if not csv_file.exists():
            print(f"❌ CSV file not found: {args.csv}")
            sys.exit(1)
        
        print(f"📄 Input: CSV file - {args.csv}")
        print(f"🔄 Converting CSV to JSON...")
        
        # Parse CSV
        test_case = parse_csv_to_json(args.csv)
        
        # Save to JSON
        json_path = f"input/{csv_file.stem}.json"
        save_json(test_case, json_path)
        
        print(f"✅ Converted to JSON: {json_path}")
        print(f"   Test Case ID: {test_case['test_case_id']}")
        print(f"   Steps: {len(test_case['steps'])}")
        print()
        
        if not args.keep_json:
            temp_json = True
    
    else:
        json_path = args.json
        json_file = Path(json_path)
        
        if not json_file.exists():
            print(f"❌ JSON file not found: {json_path}")
            sys.exit(1)
        
        print(f"📄 Input: JSON file - {json_path}")
        print()
    
    # Step 2: Generate PowerShell test script
    print(f"🤖 Initializing AI-powered test generator...")
    print(f"   Using Azure OpenAI (Azure AD authentication)")
    print()
    
    try:
        generator = TestScriptGenerator()
        
        output_path = generator.generate_and_save(
            json_path=json_path,
            output_path=args.output,
            refine=not args.no_refine
        )
        
        # Clean up temporary JSON if needed
        if temp_json and not args.keep_json:
            Path(json_path).unlink()
            print(f"🗑️  Removed temporary JSON file")
        
        print(f"\n✅ SUCCESS! Test script ready to use.")
        print(f"\n📋 Next steps:")
        print(f"   1. Review the generated script: code {output_path}")
        print(f"   2. Run as Administrator: powershell -ExecutionPolicy Bypass -File {output_path}")
        print(f"   3. Check test results in the PowerShell window")
        print()
        
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
