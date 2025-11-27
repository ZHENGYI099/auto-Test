"""
Test if workflow.invoke() is actually hanging or just slow
"""
import sys
import signal
from pathlib import Path

# Add timeout handler
def timeout_handler(signum, frame):
    print("\n⏰ TIMEOUT! Workflow invoke() has been running for 30 seconds")
    print("This means it's likely stuck in a blocking operation")
    sys.exit(1)

# Set 30 second timeout (Windows doesn't support signal.SIGALRM, so we'll just print timing)
print("🧪 Testing workflow.invoke() with timeout detection...")
print("If this hangs for >10 seconds, we know invoke() is blocking")

import time
start_time = time.time()

try:
    from core.graph import run_auto_test
    
    print(f"\n⏱️  Starting workflow.invoke() at {time.time() - start_time:.1f}s")
    final_state = run_auto_test("input/case1test.csv")
    elapsed = time.time() - start_time
    
    print(f"\n✅ Workflow completed in {elapsed:.2f} seconds")
    print(f"\nFinal state keys: {list(final_state.keys())}")
    print(f"Current step: {final_state.get('current_step')}")
    print(f"Errors: {final_state.get('errors')}")
    print(f"Execution status: {final_state.get('execution_status')}")
    
except KeyboardInterrupt:
    elapsed = time.time() - start_time
    print(f"\n⚠️  Interrupted after {elapsed:.2f} seconds")
    print("This confirms workflow.invoke() was blocking")
    sys.exit(1)
except Exception as e:
    elapsed = time.time() - start_time
    print(f"\n❌ Error after {elapsed:.2f} seconds: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
