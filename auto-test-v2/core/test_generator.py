import json
from pathlib import Path
from typing import Dict, List
from .model_client import ModelClient
from config.prompts import SYSTEM_PROMPT, TEST_GENERATION_PROMPT, REFINEMENT_PROMPT

class TestScriptGenerator:
    """Generate goal-oriented PowerShell test scripts from human steps"""
    
    def __init__(self, model_client: ModelClient = None):
        self.client = model_client or ModelClient()
    
    def load_test_case(self, json_path: str) -> Dict:
        """Load test case from JSON file"""
        with open(json_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def format_steps_context(self, steps: List[Dict]) -> str:
        """Format steps as context for AI"""
        lines = []
        for step in steps:
            step_num = step['step']
            action = step['action']
            expected = step['expected']
            
            lines.append(f"Step {step_num}:")
            lines.append(f"  Action: {action}")
            if expected:
                lines.append(f"  Expected: {expected}")
            lines.append("")
        
        return "\n".join(lines)
    
    def generate_script(self, test_case: Dict) -> str:
        """
        Generate PowerShell test script from test case
        
        Args:
            test_case: Dictionary with 'test_case_id', 'test_scenario', and 'steps'
        
        Returns:
            Generated PowerShell script as string
        """
        test_case_id = test_case['test_case_id']
        test_scenario = test_case.get('test_scenario', 'No scenario description provided')
        steps = test_case['steps']
        
        # Format steps as context
        steps_context = self.format_steps_context(steps)
        
        # Generate script with AI
        print(f"🤖 Generating test script for: {test_case_id}")
        if test_scenario:
            print(f"🎯 Test Scenario: {test_scenario}")
        print(f"📋 Analyzing {len(steps)} human operation steps...")
        
        user_prompt = TEST_GENERATION_PROMPT.format(
            test_scenario=test_scenario,
            steps_context=steps_context,
            test_case_id=test_case_id
        )
        
        script = self.client.generate(
            system_prompt=SYSTEM_PROMPT,
            user_prompt=user_prompt,
            temperature=0.2  # Low temperature for consistent output
        )
        
        print(f"✅ Script generated")
        
        return script
    
    def refine_script(self, script: str) -> str:
        """
        Refine generated script to ensure best practices
        
        Args:
            script: Generated PowerShell script
        
        Returns:
            Refined script
        """
        print(f"🔍 Refining script...")
        
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "assistant", "content": f"Generated script:\n\n{script}"},
            {"role": "user", "content": REFINEMENT_PROMPT}
        ]
        
        refinement_result = self.client.generate_with_context(
            messages=messages,
            temperature=0.1
        )
        
        # Check if refinement suggests changes
        if "no issues" in refinement_result.lower() or "looks good" in refinement_result.lower():
            print(f"✅ Script passed review")
            return script
        else:
            print(f"⚠️  Refinement suggestions found")
            print(refinement_result)
            
            # Ask AI to generate corrected version
            messages.append({"role": "assistant", "content": refinement_result})
            messages.append({"role": "user", "content": "Please provide the corrected complete PowerShell script."})
            
            refined_script = self.client.generate_with_context(
                messages=messages,
                temperature=0.1
            )
            
            print(f"✅ Script refined")
            return refined_script
    
    def extract_script_from_markdown(self, text: str) -> str:
        """Extract PowerShell script from markdown code blocks"""
        # Remove markdown code fences if present
        if "```powershell" in text:
            parts = text.split("```powershell")
            if len(parts) > 1:
                script = parts[1].split("```")[0]
                return script.strip()
        elif "```" in text:
            parts = text.split("```")
            if len(parts) >= 3:
                script = parts[1]
                return script.strip()
        
        return text.strip()
    
    def save_script(self, script: str, output_path: str):
        """Save PowerShell script to file"""
        # Extract script from markdown if needed
        clean_script = self.extract_script_from_markdown(script)
        
        # Add pause at the end if not already present
        if "ReadKey" not in clean_script and "pause" not in clean_script.lower():
            clean_script += "\n\nWrite-Host \"`nPress any key to exit...\" -ForegroundColor Cyan\n"
            clean_script += "$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')\n"
        
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Save with UTF-8 BOM for PowerShell compatibility
        output_file.write_text(clean_script, encoding='utf-8-sig')
        
        print(f"💾 Script saved to: {output_path}")
    
    def generate_and_save(self, json_path: str, output_path: str = None, refine: bool = True, config: dict = None):
        """
        Complete workflow: load JSON → generate script → refine → save
        
        Args:
            json_path: Input JSON file path
            output_path: Output .ps1 file path (optional, auto-generated if not provided)
            refine: Whether to refine the script
            config: Optional configuration dict (e.g., {'msi_path': 'C:\\path\\to.msi', 'service_name': 'ServiceName'})
        """
        # Load test case
        test_case = self.load_test_case(json_path)
        
        # Merge config into test case if provided
        if config:
            if 'config' not in test_case:
                test_case['config'] = {}
            test_case['config'].update(config)
        
        # Auto-generate output path if not provided
        if not output_path:
            test_case_id = test_case['test_case_id']
            output_path = f"output/test_{test_case_id}.ps1"
        
        # Generate script
        script = self.generate_script(test_case)
        
        # Refine if requested
        if refine:
            script = self.refine_script(script)
        
        # Save script
        self.save_script(script, output_path)
        
        print(f"\n{'='*60}")
        print(f"✅ Test script generation completed!")
        print(f"📄 Output: {output_path}")
        print(f"🚀 To run: powershell -ExecutionPolicy Bypass -File {output_path}")
        print(f"{'='*60}\n")
        
        return output_path
