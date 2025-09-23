from __future__ import annotations
import time
import os
import re
from datetime import datetime, timezone
from typing import List
from core.schemas import TestCase, EnrichedTestCase, EnrichedStep
from core.memory import GlobalSummaryMemory
from .action_agent import ActionScriptAgent
from .verify_agent import VerifyScriptAgentdot
from .refiner_agent import RefinerAgent
from .persistence_agent import PersistenceAgent
from core.prompts import ACTION_REFLECT_TEMPLATE, VERIFY_REFLECT_TEMPLATE

class CoordinatorAgent:
    def __init__(self, action_agent: ActionScriptAgent, verify_agent: VerifyScriptAgent,
                 refiner: RefinerAgent, persistence: PersistenceAgent, memory: GlobalSummaryMemory,
                 deployment: str):
        self.action_agent = action_agent
        self.verify_agent = verify_agent
        self.refiner = refiner
        self.persistence = persistence
        self.memory = memory
        self.deployment = deployment

    def run(self, test_case: TestCase, output_path: str, rate_limit_sec: float = 0.5):
        enriched_steps: List[EnrichedStep] = []
        for step in test_case.steps:
            state_summary = self.memory.summary()
            current_dir = self.memory.working_directory()
            state_full_json = self.memory.state_object()
            # Compact JSON serialization without importing json here (manual minimal build)
            try:
                import json as _json
                state_full_str = _json.dumps(state_full_json, ensure_ascii=False)
            except Exception:
                state_full_str = str(state_full_json)
            action_script = self.action_agent.generate(step.action, state_summary, current_dir, state_full_str)
            action_script = self.refiner.refine(action_script)
            # Hard injection
            action_script = self._ensure_working_directory(action_script)
            # Fallback: if memory has no current_dir but action_script opens explorer to path
            if self.memory.working_directory() == '(not set)':
                m_ex = re.search(r"(?i)Start-Process\s+explorer.exe\s+'([^']+)'", action_script)
                if m_ex:
                    # Directly set memory current_dir for subsequent steps
                    self.memory.current_dir = m_ex.group(1)
                    # Re-run ensure working directory if later steps in same loop body need it
                    action_script = self._ensure_working_directory(action_script)
            # Reflection pass for action
            if os.environ.get('REFLECT_FIX', '1') == '1' and self._needs_reflection(action_script):
                action_script = self._reflect_action(action_script)
            # Remove pure comment script per no-comment requirement
            if action_script.strip().startswith('#') and '\n' not in action_script.strip():
                action_script = ''
            action_script = self._normalize_line_separators(action_script)
            verify_script = None
            if step.expected and step.expected.strip():
                verify_script = self.verify_agent.generate(step.action, step.expected, self.memory.summary(), current_dir, state_full_str)
                verify_script = self.refiner.refine(verify_script)
                verify_script = self._ensure_working_directory(verify_script)
                if os.environ.get('REFLECT_FIX', '1') == '1' and self._needs_reflection(verify_script):
                    verify_script = self._reflect_verify(verify_script)
                verify_script = self._normalize_line_separators(verify_script)
            enriched = EnrichedStep(
                step=step.step,
                action=step.action,
                expected=step.expected,
                action_script=action_script,
                verify_script=verify_script
            )
            enriched_steps.append(enriched)
            self.memory.add(step.step, step.action, action_script, verify_script)
            time.sleep(rate_limit_sec)
        enriched_case = EnrichedTestCase(
            test_case_id=test_case.test_case_id,
            generated_at=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            model_deployment=self.deployment,
            steps=enriched_steps
        )
        self.persistence.write(enriched_case, output_path)
        return enriched_case

    # --- Helpers ---
    def _ensure_working_directory(self, script: str) -> str:
        if not script:
            return script
        current_dir = self.memory.working_directory()
        if current_dir == '(not set)':
            return script
        lower = script.lower()
        if 'powershell' in lower:
            has_cd = ('set-location' in lower) or ('-workingdirectory' in lower)
            if not has_cd:
                if 'start-process' in lower and 'powershell' in lower:
                    script = re.sub(r"(?i)start-process\s+powershell.exe", f"Start-Process powershell.exe -WorkingDirectory '{current_dir}'", script, count=1)
                else:
                    script = f"Set-Location -LiteralPath '{current_dir}'\n" + script
        return script

    def _needs_reflection(self, script: str) -> bool:
        if not script:
            return False
        current_dir = self.memory.working_directory()
        if current_dir == '(not set)':
            return False
        # If it starts or launches PowerShell or does file operations but lacks any directory context
        indicators = ['start-process', 'copy-item', 'move-item', 'invoke-item', 'get-childitem', 'new-item', 'msi']
        lower = script.lower()
        if any(ind in lower for ind in indicators):
            if ('set-location' not in lower) and ('-workingdirectory' not in lower) and (current_dir.lower() not in lower):
                return True
        return False

    def _reflect_action(self, script: str) -> str:
        try:
            prompt = ACTION_REFLECT_TEMPLATE.format(script=script, current_dir=self.memory.working_directory())
            result = self.action_agent.model.chat("Return only script.", prompt)
            if result and result.content:
                return result.content.strip()
        except Exception:
            return script
        return script

    def _reflect_verify(self, script: str) -> str:
        try:
            prompt = VERIFY_REFLECT_TEMPLATE.format(script=script, current_dir=self.memory.working_directory())
            result = self.verify_agent.model.chat("Return only script.", prompt)
            if result and result.content:
                return result.content.strip()
        except Exception:
            return script
        return script

    def _normalize_line_separators(self, script: str) -> str:
        if not script:
            return script
        # Replace literal \n tokens that appear inside the string as text (not actual newlines)
        # Heuristic: if contains "\\n" sequence.
        if "\\n" in script:
            # Split on literal \n, then trim each part
            parts = [p.strip() for p in script.split("\\n") if p.strip()]
            # If parts look like multiple commands, join with real newline; else return original
            if len(parts) > 1:
                # Prefer real newline for readability
                script = "\n".join(parts)
        return script
