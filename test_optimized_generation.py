"""
Test script to verify optimized test case generation with new prompts.
This will regenerate the test case 34714753 and compare with original.
"""
import sys
import os
import json
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.model_client import ModelClient
from core.memory import GlobalSummaryMemory
from core.schemas import TestCase, Step
from agents.action_agent import ActionScriptAgent
from agents.verify_agent import VerifyScriptAgent
from agents.refiner_agent import RefinerAgent
from agents.persistence_agent import PersistenceAgent
from agents.coordinator_agent import CoordinatorAgent

def load_csv_test_case():
    """Simulate loading test case 34714753 from CSV"""
    steps = [
        Step(step=1, action="Apply to all devices.", expected=""),
        Step(
            step=2,
            action='Press "Win + E" keys, open File Explorer, go to the folder where "cmdextension.msi" locates,cmdextension.msi locates in C:\\VMShare',
            expected=""
        ),
        Step(
            step=3,
            action='In file explorer, click on "File -> Open Windows PowerShell -> Open Windows PowerShell as administrator"',
            expected=""
        ),
        Step(
            step=4,
            action="Run command: msiexec /i cmdextension.msi /qn+",
            expected='The prompt window should pop up: Title is "Microsoft Cloud Manage Desktop Extension", and Message is "Microsoft Cloud Managed Desktop Extension Setup completed successfully."\n\nIf the step failed, run: msiexec /i cmdextension.msi /qn+ /l*v mylog. Send mylog to CMD Agent team for troubleshooting'
        ),
        Step(
            step=5,
            action='Open "Control Panel -> Programs -> Uninstall a program"',
            expected='Verify "Microsoft Cloud Managed Desktop Extension" is present in the list of installed programs.'
        ),
        Step(
            step=6,
            action='Open "Task Manager -> Services"',
            expected='Verify "CloudManagedDesktopExtension"\nis in running state.'
        ),
        Step(
            step=7,
            action='Press "Win + R" keys, type "services.msc" and press Enter.',
            expected='Verify "Microsoft Cloud Managed Desktop Extension" - Status is "Running", Startup Type is "Automatic (Delayed Start)", and Log On As is "Local System".'
        ),
        Step(
            step=8,
            action='Open file explorer, go to %ProgramData%\\Microsoft\\CMDExtension\\Logs.',
            expected='Verify "CMDExtension.log" is present.'
        ),
        Step(
            step=9,
            action='Press "Win + R" keys, type "taskschd.msc" and press Enter. Open "Task scheduler library -> Microsoft -> CMD"',
            expected='Verify "Cloud Managed Desktop Extension Health Evaluation" is present.'
        ),
        Step(
            step=10,
            action='Press "Win + R" keys, type "wbemtest" and press Enter. Click on "Connect", type "root\\cmd\\clientagent" and press Enter.',
            expected='Verify there is NOT error prompt window which displays "Invalid namespace".'
        ),
        Step(
            step=11,
            action='Test Cleanup:\n\n\nIn the same PowerShell window as "Step 3", run command: msiexec /x cmdextension.msi',
            expected=""
        )
    ]
    return TestCase(test_case_id="testcase-34714753", steps=steps)

def main():
    print("🚀 Testing Optimized Test Case Generation")
    print("=" * 60)
    
    # Initialize model client
    model = ModelClient()
    deployment = model.deployment
    
    # Initialize agents
    memory = GlobalSummaryMemory()
    action_agent = ActionScriptAgent(model)
    verify_agent = VerifyScriptAgent(model)
    refiner = RefinerAgent()
    persistence = PersistenceAgent()
    
    coordinator = CoordinatorAgent(
        action_agent=action_agent,
        verify_agent=verify_agent,
        refiner=refiner,
        persistence=persistence,
        memory=memory,
        deployment=deployment
    )
    
    # Load test case
    test_case = load_csv_test_case()
    print(f"📋 Test Case ID: {test_case.test_case_id}")
    print(f"📝 Total Steps: {len(test_case.steps)}")
    print()
    
    # Generate optimized test case
    output_path = "outputs/34714753.optimized.json"
    print(f"⚙️  Generating optimized test case...")
    print(f"📁 Output: {output_path}")
    print()
    
    enriched = coordinator.run(test_case, output_path, rate_limit_sec=1.0)
    
    # Compare with original
    original_path = "outputs/34714753.coordinator.json"
    if os.path.exists(original_path):
        print("\n" + "=" * 60)
        print("📊 COMPARISON: Original vs Optimized")
        print("=" * 60)
        
        with open(original_path, 'r', encoding='utf-8') as f:
            original = json.load(f)
        
        for i, (orig_step, opt_step) in enumerate(zip(original['steps'], enriched.steps), 1):
            action_changed = orig_step['action_script'] != opt_step.action_script
            verify_changed = orig_step.get('verify_script') != opt_step.verify_script
            
            if action_changed or verify_changed:
                print(f"\n📌 Step {i}: {opt_step.action[:60]}...")
                
                if action_changed:
                    print(f"  ⚡ ACTION OPTIMIZED:")
                    print(f"     ❌ Original: {orig_step['action_script'][:80]}")
                    print(f"     ✅ Optimized: {opt_step.action_script[:80]}")
                
                if verify_changed:
                    print(f"  🔍 VERIFY OPTIMIZED:")
                    print(f"     ❌ Original: {str(orig_step.get('verify_script'))[:80]}")
                    print(f"     ✅ Optimized: {str(opt_step.verify_script)[:80]}")
    
    print("\n" + "=" * 60)
    print("✅ Generation Complete!")
    print(f"📄 Generated file: {output_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
