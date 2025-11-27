"""
Debug script to test workflow step by step
"""
from core.state import create_initial_state
from core.nodes.parse import parse_csv_node
from core.nodes.generate import generate_script_node
from core.nodes.validate import validate_script_node

# Create initial state
print("Step 1: Creating initial state...")
state = create_initial_state("input/case1test.csv")
print(f"✅ Initial state created: {state['test_case_id']}")

# Parse CSV
print("\nStep 2: Parsing CSV...")
state = parse_csv_node(state)
print(f"✅ CSV parsed: {state.get('parsed_data', {}).get('test_case_id', 'unknown')}")
if state.get('errors'):
    print(f"❌ Errors: {state['errors']}")
    exit(1)

# Generate script
print("\nStep 3: Generating script...")
state = generate_script_node(state)
print(f"✅ Script path: {state.get('generated_script_path', 'NOT SET')}")
if state.get('errors'):
    print(f"❌ Errors: {state['errors']}")
    exit(1)

# Validate script
print("\nStep 4: Validating script...")
state = validate_script_node(state)
print(f"✅ Validation passed: {state.get('validation_passed', False)}")
print(f"   Issues: {len(state.get('validation_issues', []))}")
if state.get('errors'):
    print(f"❌ Errors: {state['errors']}")
    exit(1)

print("\n🎉 All steps completed successfully!")
print(f"Final state keys: {list(state.keys())}")
