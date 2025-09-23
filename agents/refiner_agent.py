from __future__ import annotations
import re

class RefinerAgent:
    """Lightweight static refinement / safety filters."""
    DANGEROUS_PATTERNS = [
        r"Remove-Item\s+-Recurse\s+C:\\",
        r"Format-",
        r"Stop-Service\s+.+-Force"
    ]

    def refine(self, script: str) -> str:
        cleaned = script.strip()
        for pat in self.DANGEROUS_PATTERNS:
            if re.search(pat, cleaned, re.IGNORECASE):
                return "throw 'BLOCKED_DANGEROUS_COMMAND'"
        return cleaned
