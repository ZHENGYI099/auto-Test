import json
import time
from typing import Dict, Any, List

from dotenv import load_dotenv
from core.model_client import ModelClient

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


def generate_scripts_for_step(client: ModelClient, action: str, expected: str) -> Dict[str, str]:
    """使用 ModelClient 生成 action 和 verify 脚本"""
    action_prompt = ACTION_PROMPT_TEMPLATE.format(action=action.strip())
    action_script = client.chat("You output only raw PowerShell.", action_prompt, max_tokens=300)
    
    result = {"action_script": action_script}
    
    if expected and expected.strip():
        verify_prompt = VERIFY_PROMPT_TEMPLATE.format(action=action.strip(), expected=expected.strip())
        verify_script = client.chat("You output only raw PowerShell.", verify_prompt, max_tokens=300)
        result["verify_script"] = verify_script
    
    return result


def enrich_test_case(input_path: str, output_path: str, rate_limit_sec: float = 1.0) -> Dict[str, Any]:
    """读取测试用例 JSON，为每个步骤生成 PowerShell 脚本"""
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    steps: List[Dict[str, Any]] = data.get('steps', [])
    client = ModelClient()
    
    enriched_steps = []
    for i, step_obj in enumerate(steps, 1):
        action = step_obj.get('action', '')
        expected = step_obj.get('expected', '')
        
        print(f"正在处理步骤 {i}/{len(steps)}: {action[:50]}...")
        
        try:
            scripts = generate_scripts_for_step(client, action, expected)
        except Exception as e:
            print(f"  ⚠️  生成失败: {e}")
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
        "model_deployment": client.deployment,
        "steps": enriched_steps
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(enriched_data, f, indent=2, ensure_ascii=False)

    return enriched_data


def main():
    import argparse
    
    load_dotenv()
    
    parser = argparse.ArgumentParser(
        description="为测试用例的每个步骤生成 PowerShell 自动化脚本（使用无密钥 Azure AD 认证）"
    )
    parser.add_argument('-i', '--input', required=True, help='输入的测试用例 JSON 文件路径')
    parser.add_argument('-o', '--output', help='输出的增强 JSON 文件路径（默认：输入文件名.enriched.json）')
    parser.add_argument('--no-wait', action='store_true', help='不在 API 调用之间等待（可能触发限流）')
    args = parser.parse_args()

    # 自动生成输出文件名
    if not args.output:
        input_name = args.input.replace('.json', '')
        args.output = f"{input_name}.enriched.json"
    
    wait = 0.0 if args.no_wait else 1.0
    
    print(f"📖 读取输入: {args.input}")
    print(f"🔐 使用 Azure AD 无密钥认证")
    print(f"⏱️  API 调用间隔: {wait}秒\n")
    
    result = enrich_test_case(args.input, args.output, rate_limit_sec=wait)
    
    print(f"\n✅ 完成！已写入 {args.output}")
    print(f"   生成了 {len(result.get('steps', []))} 个步骤的脚本")


if __name__ == '__main__':
    main()
