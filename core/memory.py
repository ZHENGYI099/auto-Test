from __future__ import annotations
from typing import List, Dict, Any
from dataclasses import dataclass
import re

@dataclass
class MemoryItem:
    step: int
    action_summary: str
    action_script: str
    verify_script: str | None

class GlobalSummaryMemory:
    """Maintains a running textual summary + current working directory + structured state."""
    PATH_REGEX = re.compile(r"[A-Za-z]:\\\\[\\w .\\-\\\\]+")
    MSI_REGEX = re.compile(r"[A-Za-z]:\\\\[\\w .\\-\\\\]+\.msi", re.IGNORECASE)

    def __init__(self) -> None:
        self.items: List[MemoryItem] = []
        self._summary: str = "(empty)"
        self.current_dir: str | None = None
        self.msi_paths: List[str] = []
        self.full_steps: List[Dict[str, Any]] = []  # full history

    def _extract_path(self, text: str):
        match = self.PATH_REGEX.search(text.replace('\\\n', ' '))
        cleaned = text.replace('\n', ' ').replace('“', '"').replace('”', '"')
        match = self.PATH_REGEX.search(cleaned)
        if match:
            candidate = match.group(0).rstrip('"').rstrip("'")
            # If looks like an MSI file path, use its directory
            if candidate.lower().endswith('.msi'):
                import os as _os
                return _os.path.dirname(candidate) or candidate
            return candidate
        # Heuristic: phrase 'locates in C:\\Something'
        m2 = re.search(r"locates in\s+([A-Za-z]:\\\\[\\w .\\-\\\\]+)", cleaned, re.IGNORECASE)
        if m2:
            return m2.group(1)
        return None

    def add(self, step: int, action: str, action_script: str, verify_script: str | None):
        found = self._extract_path(action)
        if found:
            self.current_dir = found
        # collect msi references
        for segment in (action, action_script):
            for m in self.MSI_REGEX.findall(segment):
                if m not in self.msi_paths:
                    self.msi_paths.append(m)
        line = f"Step {step}: action='{action[:60].replace('\n',' ')}'" + (f" (cwd={self.current_dir})" if self.current_dir else "")
        self.items.append(MemoryItem(step, line, action_script, verify_script))
        self.full_steps.append({
            'step': step,
            'action': action,
            'action_script': action_script,
            'verify_script': verify_script
        })
        self._rebuild_summary()

    def _rebuild_summary(self):
        parts = []
        for it in self.items:
            parts.append(it.action_summary)
        self._summary = "\n".join(parts) if parts else "(empty)"

    def summary(self) -> str:
        return self._summary

    def working_directory(self) -> str:
        return self.current_dir or "(not set)"

    def state_object(self) -> Dict[str, Any]:
        return {
            'current_dir': self.current_dir,
            'msi_files': self.msi_paths,
            'completed_steps': [
                {'step': s['step'], 'has_verify': bool(s['verify_script']), 'action_excerpt': s['action'][:80]} for s in self.full_steps
            ]
        }
