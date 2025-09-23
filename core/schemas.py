from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel, Field

class Step(BaseModel):
    step: int
    action: str
    expected: Optional[str] = ""

class EnrichedStep(Step):
    action_script: str
    verify_script: Optional[str] = None

class TestCase(BaseModel):
    test_case_id: str = Field(..., alias="test_case_id")
    steps: List[Step]

class EnrichedTestCase(BaseModel):
    test_case_id: str
    generated_at: str
    model_deployment: str
    steps: List[EnrichedStep]
