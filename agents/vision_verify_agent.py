from __future__ import annotations
import json
from typing import Any, Dict, List
from core.prompts import VISION_VERIFY_PROMPT_TEMPLATE
from core.model_client import ModelClient

class VisionVerifyAgent:
    """Agent wrapper to perform screenshot-based verification using multi-modal chat."""
    def __init__(self, model: ModelClient):
        self.model = model

    def verify(self, image_b64: str, expected: str, title: str = "") -> Dict[str, Any]:
        prompt = VISION_VERIFY_PROMPT_TEMPLATE.format(title=title.strip(), expected=expected.strip())
        messages: List[Dict[str, Any]] = [
            {
                'role': 'user',
                'content': [
                    {'type': 'text', 'text': prompt},
                    {'type': 'image_url', 'image_url': {'url': f'data:image/png;base64,{image_b64}'}}
                ]
            }
        ]
        raw = self.model.chat_messages(messages, temperature=0.0, max_tokens=400)
        # Try to isolate JSON object
        import re
        match = re.search(r"\{.*\}", raw, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except Exception:
                pass
        return {"status": "fail", "reason": "Unparseable model output", "raw": raw}
