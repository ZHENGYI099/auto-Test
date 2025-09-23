from __future__ import annotations
from core.prompts import ACTION_PROMPT_TEMPLATE
from core.model_client import ModelClient

class ActionScriptAgent:
    def __init__(self, model: ModelClient):
        self.model = model

    def generate(self, action: str, state_summary: str, current_dir: str, state_full: str) -> str:
        prompt = ACTION_PROMPT_TEMPLATE.format(action=action.strip(), state_summary=state_summary, current_dir=current_dir, state_full=state_full)
        return self.model.chat("You output only raw PowerShell.", prompt)
