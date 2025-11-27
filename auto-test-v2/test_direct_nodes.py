"""
Test calling nodes directly without LangGraph
直接调用节点函数,不通过 LangGraph
"""
from core.state import create_initial_state
from core.nodes.parse import parse_csv_node
from core.nodes.generate import generate_script_node

def test_direct():
    print("=" * 60)
    print("🧪 Testing Direct Node Calls (No LangGraph)")
    print("=" * 60)
    
    # Step 1: Create initial state
    print("\n1️⃣ Creating initial state...")
    state = create_initial_state("auto-test-v2/input/case1test.csv", "")
    print(f"✅ Initial state created")
    print(f"   CSV Path: {state['csv_path']}")
    
    # Step 2: Parse CSV
    print("\n2️⃣ Calling parse_csv_node...")
    state = parse_csv_node(state)
    print(f"✅ Parse completed")
    print(f"   Parsed data: {bool(state.get('parsed_data'))}")
    print(f"   Errors: {state.get('errors', [])}")
    
    if not state.get("parsed_data"):
        print("❌ Parsing failed, stopping")
        return
    
    # Step 3: Generate script
    print("\n3️⃣ Calling generate_script_node...")
    print("   This is where it gets stuck in LangGraph...")
    state = generate_script_node(state)
    print(f"✅ Generation completed!")
    print(f"   Script path: {state.get('generated_script_path')}")
    print(f"   Has content: {bool(state.get('generated_script_content'))}")
    print(f"   Errors: {state.get('errors', [])}")
    
    print("\n" + "=" * 60)
    print("✅ Direct node calls work fine!")
    print("=" * 60)

if __name__ == "__main__":
    test_direct()
