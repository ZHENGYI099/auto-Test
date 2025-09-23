ACTION_PROMPT_TEMPLATE = (
    "You are an expert Windows automation engineer. Given a test step's action description, "
    "produce an idempotent Windows PowerShell script fragment that performs ONLY the action. Rules: \n"
    "- Output ONLY raw PowerShell lines (no markdown, no comments, no explanations).\n"
    "- Prefer built-in commands; avoid third-party modules.\n"
    "- Do not include validation or assertions here; only perform the action.\n"
    "- If the action is purely navigational (opening a GUI), just launch it.\n"
    "- If starting PowerShell (elevated or not) and Current Working Directory is not '(not set)', you MUST either: use -WorkingDirectory '{current_dir}' OR first line Set-Location -LiteralPath '{current_dir}'.\n"
    "- Do NOT output the two characters \\n as a literal for line breaks. Use a real newline (line break) or PowerShell command separator ';'.\n"
    "- Avoid repeating previous completed installations or openings unless explicitly required.\n\n"
    "Current Working Directory (if set): {current_dir}\n"
    "Structured State (JSON):\n{state_full}\n\n"
    "Global State Summary (textual):\n{state_summary}\n\n"
    "Action: {action}\n"
    "Action Script:\n"
)

VERIFY_PROMPT_TEMPLATE = (
    "You are an expert Windows automation QA engineer. Given a test step with an expected result, "
    "generate a PowerShell script fragment that VALIDATES ONLY the expected outcome. Rules:\n"
    "- Output ONLY raw PowerShell lines (no markdown, no comments).\n"
    "- Use exit codes: exit 0 on success, exit 1 on failure if practical.\n"
    "- If GUI-only visual confirmation is required and cannot be programmatically verified, output a single line: throw 'MANUAL_CHECK'.\n"
    "- Do not perform the original action again.\n"
    "- Be idempotent and safe.\n"
    "- Assume current working directory if provided; otherwise use absolute paths. If verifying something inside the working directory, you MUST reference it using either relative path or Join-Path '{current_dir}'.\n"
    "- Do NOT output the two characters \\n as a literal for line breaks. Use real newlines or ';'.\n\n"
    "Current Working Directory (if set): {current_dir}\n"
    "Structured State (JSON):\n{state_full}\n\n"
    "Global State Summary (textual):\n{state_summary}\n\n"
    "Action (context): {action}\n"
    "Expected: {expected}\n"
    "Verification Script:\n"
)

# Reflection templates
ACTION_REFLECT_TEMPLATE = (
    "You previously generated this PowerShell action script:\n{script}\n\n"
    "Current Working Directory: {current_dir}\n"
    "Requirements: If the script launches PowerShell or operates on files that are located inside the working directory, it MUST either use -WorkingDirectory '{current_dir}' or begin with Set-Location -LiteralPath '{current_dir}'.\n"
    "If the requirement is already satisfied, return the script unchanged. If not, output a corrected minimal script. Output ONLY the final script, no commentary.\n"
)

VERIFY_REFLECT_TEMPLATE = (
    "You previously generated this PowerShell verification script:\n{script}\n\n"
    "Current Working Directory: {current_dir}\n"
    "If the verification references artifacts (files, logs, msi) expected inside the working directory and does not use the directory explicitly or via relative path after ensuring Set-Location, prepend or adjust accordingly.\n"
    "Return ONLY the corrected script (or the same if already correct).\n"
)

# Vision verification prompt (English) for unified style
VISION_VERIFY_PROMPT_TEMPLATE = (
    "You are a GUI installation/result verification assistant. You will be given: \n"
    "1) An optional window title (may be empty).\n"
    "2) Expected key textual content that should appear in the screenshot.\n"
    "You must decide if the screenshot likely shows the expected successful state.\n"
    "Guidelines:\n"
    "- Perform case-insensitive, whitespace-insensitive, and minor punctuation tolerant matching.\n"
    "- The expected text may appear partially (e.g., truncated window title) but should be semantically present.\n"
    "- If multiple tokens are provided, success requires most core tokens (ignore trivial stopwords).\n"
    "- Be robust to UI styling differences (icons, buttons).\n"
    "- If the screenshot clearly indicates an error, failure, or missing expected content, return fail.\n"
    "Output strictly JSON with keys: {\"status\": \"success\"|\"fail\", \"reason\": \"short justification\"}. \n"
    "Do NOT output anything else.\n"
    "Window Title (may be empty): '{title}'\n"
    "Expected Content: '{expected}'\n"
    "Return JSON only:"
)

# Minimal vision prompt for simple one-off verification
VISION_SIMPLE_PROMPT_TEMPLATE = (
    "You are a GUI result checker. A single screenshot is provided.\n"
    "Expected semantic/text content: '{expected}'.\n"
    "Return STRICT JSON only: {{\"status\": \"success\"|\"fail\", \"reason\": \"short justification\"}}.\n"
    "Be tolerant to case, whitespace and minor punctuation differences."
)
