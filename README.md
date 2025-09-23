# Test Case eshell Script Generator

This repository includes a utility to enrich a test case JSON (e.g. `34717304.json`) by generating a PowerShell ("eshell") script fragment for each step using Azure OpenAI.

## Prerequisites
1. Python 3.9+
2. Azure OpenAI resource with a deployment (e.g. `gpt-4.1`).
3. `.env` file populated with:
```
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_ENDPOINT=...
AZURE_OPENAI_API_VERSION=2025-04-01-preview
AZURE_OPENAI_DEPLOYMENT=gpt-4.1
```

## Install
```powershell
pip install -r requirements.txt
```

## Run
Generate enriched JSON (default input `34717304.json`, output `34717304.enriched.json`):
```powershell
python generate_eshell.py
```
Disable wait (faster, higher risk of rate limit):
```powershell
python generate_eshell.py --no-wait
```
Specify custom files:
```powershell
python generate_eshell.py -i mycase.json -o mycase.enriched.json
```

## Output Structure
`*.enriched.json` fields:
- `test_case_id`: Original id
- `generated_at`: UTC timestamp
- `model_deployment`: Deployment name used
- `steps[]`: For each step:
  - original fields (`step`, `action`, `expected`)
  - `action_script`: PowerShell fragment performing the action only
  - `verify_script`: (only when `expected` non-empty) PowerShell fragment validating expected result (exit 0 success, exit 1 failure if possible; may `throw 'MANUAL_CHECK'` if cannot be automated)

## Notes
- `expected` 为空时不生成 `verify_script`。
- Scripts不包含注释；验证脚本可用 `exit 1`/`throw` 表示失败。
- Any generation error is captured inline per step to avoid aborting the whole process.

## Multi-Agent Architecture (Pluggable)
The project now supports an optional multi-agent layout (see `agents/` and `core/`):
- `ActionScriptAgent`: Generates action-only script using global state summary.
- `VerifyScriptAgent`: Generates verification script when expected is present.
- `RefinerAgent`: Applies static safety filters (blocks dangerous patterns).
- `PersistenceAgent`: Writes enriched JSON artifact.
- `CoordinatorAgent`: Orchestrates per-step flow, updates global memory summary.
- `GlobalSummaryMemory`: Maintains a compressed textual summary of prior steps for context injection.
  - Now also extracts first explicit Windows path mentioned in an action and treats it as current working directory.
  - Tracks discovered `.msi` file paths and passes them in structured JSON state for subsequent steps.

Run the multi-agent pipeline:
```powershell
python scripts/run_enrich.py -i 34717304.json -o outputs/34717304.enriched.json
```

Planned extensions:
- Retrieval-augmented memory (vector search over past steps)
- Parallel generation with rate limiting
- Policy-based refinement (semantic validations)
- Persistent structured state (JSON) capturing working directory, installed components, services validated
 - MSI install context reuse (avoid re-install prompts, provide cached path variable)
- Adjust temperature or max tokens inside `generate_eshell.py` if needed.

## GUI / Vision Verification (Optional)
Some steps cannot be reliably auto‑verified (pure GUI popups). Instead of `throw 'MANUAL_CHECK'`, you can use the provided vision workflow:

1. Capture a screenshot of the popup/window (focused or full screen).
2. Send the image plus textual expectation to Azure OpenAI Vision.
3. Parse JSON result: `{ "status": "success" | "fail", "reason": "..." }`.

### Files
- `scripts/capture_and_verify.ps1`: PowerShell helper to poll for a window title, capture screenshot (fallback full screen), then call Python verifier.
- `verify/vision_verify.py`: Python script sending the image to Azure OpenAI Vision deployment.

### Environment Variables
```
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_ENDPOINT=...
AZURE_OPENAI_DEPLOYMENT_VISION=gpt-4.1   # or your vision-capable deployment
```

### Example Usage
```powershell
python verify/vision_verify.py --image popup.png --expect "Setup completed successfully" --title "Microsoft Cloud Managed Desktop Extension"

# Or end-to-end capture + verify:
powershell -ExecutionPolicy Bypass -File scripts/capture_and_verify.ps1 -ImagePath popup.png -ExpectText "Setup completed successfully" -WindowTitle "Microsoft Cloud Managed Desktop Extension"
```

Exit codes:
- 0 = success (expected text detected)
- 1 = fail (not detected)
- 2/3 = client / runtime errors

You can integrate this by replacing `throw 'MANUAL_CHECK'` in generated verify scripts with a call to the capture+verify flow.

