import os
import json
import time
from typing import Dict, Any, List

from dotenv import load_dotenv
from openai import AzureOpenAI

ACTION_PROMPT_TEMPLATE = (
    "You are an expert Windows automation engineer. Given a test step's action description, "
    "produce an idempotent Windows PowerShell script fragment that performs ONLY the action. Rules: \n"
    "- Output ONLY raw PowerShell lines (no markdown, no comments, no explanations).\n"
    "- Prefer built-in commands; avoid third-party modules.\n"
    "- Do not include validation or assertions here; only perform the action.\n"
    "- If the action is purely navigational (opening a GUI), just launch it.\n\n"
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
    "- Be idempotent and safe.\n\n"
    "Action (context): {action}\n"
    "Expected: {expected}\n"
    "Verification Script:\n"
)


def build_client() -> AzureOpenAI:
    endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    key = os.getenv("AZURE_OPENAI_API_KEY")
    api_version = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
    if not endpoint or not key:
        raise RuntimeError("Missing Azure OpenAI credentials in environment.")
    return AzureOpenAI(azure_endpoint=endpoint, api_key=key, api_version=api_version)


def _call_model(client: AzureOpenAI, deployment: str, system: str, user: str) -> str:
    resp = client.chat.completions.create(
        model=deployment,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        temperature=0.0,
        max_tokens=300
    )
    content = resp.choices[0].message.content.strip()
    if content.startswith("```"):
        lines = content.splitlines()
        if len(lines) >= 2 and lines[-1].startswith("```"):
            content = "\n".join(lines[1:-1]).strip()
    return content


def generate_scripts_for_step(client: AzureOpenAI, deployment: str, action: str, expected: str) -> Dict[str, str]:
    action_prompt = ACTION_PROMPT_TEMPLATE.format(action=action.strip())
    action_script = _call_model(client, deployment, "You output only raw PowerShell.", action_prompt)
    result = {"action_script": action_script}
    if expected and expected.strip():
        verify_prompt = VERIFY_PROMPT_TEMPLATE.format(action=action.strip(), expected=expected.strip())
        verify_script = _call_model(client, deployment, "You output only raw PowerShell.", verify_prompt)
        result["verify_script"] = verify_script
    return result


def enrich_test_case(input_path: str, output_path: str, rate_limit_sec: float = 1.0) -> Dict[str, Any]:
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    steps: List[Dict[str, Any]] = data.get('steps', [])
    client = build_client()
    deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")

    enriched_steps = []
    for step_obj in steps:
        action = step_obj.get('action', '')
        expected = step_obj.get('expected', '')
        try:
            scripts = generate_scripts_for_step(client, deployment, action, expected)
        except Exception as e:
            scripts = {"action_script": f"throw 'GENERATION_ERROR: {e}'"}
        enriched = dict(step_obj)
        enriched['action_script'] = scripts['action_script']
        if 'verify_script' in scripts:
            enriched['verify_script'] = scripts['verify_script']
        enriched_steps.append(enriched)
        time.sleep(rate_limit_sec)

    enriched_data = {
        "test_case_id": data.get("test_case_id"),
        "generated_at": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        "model_deployment": deployment,
        "steps": enriched_steps
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(enriched_data, f, indent=2, ensure_ascii=False)

    return enriched_data


def main():
    import argparse
    load_dotenv()
    parser = argparse.ArgumentParser(description="Generate eshell PowerShell fragments for each test step.")
    parser.add_argument('-i', '--input', default='34717304.json', help='Input test case JSON file')
    parser.add_argument('-o', '--output', default='34717304.enriched.json', help='Output enriched JSON file')
    parser.add_argument('--no-wait', action='store_true', help='Do not sleep between API calls')
    args = parser.parse_args()

    wait = 0.0 if args.no_wait else 1.0
    result = enrich_test_case(args.input, args.output, rate_limit_sec=wait)
    print(f"Wrote {args.output} with {len(result.get('steps', []))} steps.")


if __name__ == '__main__':
    main()
