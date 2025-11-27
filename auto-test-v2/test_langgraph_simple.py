"""
Minimal test to isolate the LangGraph issue
"""
import sys
import os
from pathlib import Path

# Fix Windows console encoding
if sys.platform == "win32":
    os.system("")  # Enable ANSI
    sys.stdout.reconfigure(encoding='utf-8')

print("=" * 60)
print("Step 1: Import modules")
print("=" * 60)

from core.state import create_initial_state
print("✅ Imported create_initial_state")

from core.graph import auto_test_workflow
print("✅ Imported auto_test_workflow")

print("\n" + "=" * 60)
print("Step 2: Create initial state")
print("=" * 60)

initial_state = create_initial_state("input/case1test.csv", "case1test")
print(f"✅ Initial state created")
print(f"   Keys: {list(initial_state.keys())[:5]}...")

print("\n" + "=" * 60)
print("Step 3: Test LangGraph stream (with timeout)")
print("=" * 60)

import signal

def timeout_handler(signum, frame):
    print("\n⏰ TIMEOUT! LangGraph is hanging!")
    print("This confirms the issue is with LangGraph workflow execution")
    sys.exit(1)

# Set 30 second timeout (Windows doesn't support signal.SIGALRM)
# So we'll just try to iterate and print progress

step_count = 0
try:
    print("Starting stream iteration...")
    for step in auto_test_workflow.stream(initial_state):
        step_count += 1
        print(f"\n📍 Step {step_count}: {list(step.keys())}")
        
        # Print step details
        for node_name, state in step.items():
            current_step = state.get("current_step", "unknown")
            errors = state.get("errors", [])
            print(f"   Node: {node_name}")
            print(f"   Current step: {current_step}")
            if errors:
                print(f"   Errors: {errors}")
        
        # Safety check - if we're stuck in a loop
        if step_count > 20:
            print("\n⚠️  Too many steps! Possible infinite loop")
            break
            
except KeyboardInterrupt:
    print("\n⚠️  Interrupted by user")
    sys.exit(1)
except Exception as e:
    print(f"\n❌ Error during streaming: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print(f"\n✅ Stream completed after {step_count} steps")
