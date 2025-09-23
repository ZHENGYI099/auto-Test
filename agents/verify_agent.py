from __future__ import annotations
from core.prompts import VERIFY_PROMPT_TEMPLATE
from core.model_client import ModelClient

class VerifyScriptAgent:
    def __init__(self, model: ModelClient):
        self.model = model

    def generate(self, action: str, expected: str, state_summary: str, current_dir: str, state_full: str) -> str:
        prompt = VERIFY_PROMPT_TEMPLATE.format(action=action.strip(), expected=expected.strip(), state_summary=state_summary, current_dir=current_dir, state_full=state_full)
        return self.model.chat("You output only raw PowerShell.", prompt)
