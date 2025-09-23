from __future__ import annotations
import json
from typing import List
from core.schemas import EnrichedStep, EnrichedTestCase

class PersistenceAgent:
    def write(self, enriched: EnrichedTestCase, path: str):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(enriched.model_dump(), f, indent=2, ensure_ascii=False)
