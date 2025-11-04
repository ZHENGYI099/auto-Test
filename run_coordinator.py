"""
使用 CoordinatorAgent 运行完整的测试用例增强流程
包含记忆、优化、反射等高级特性
"""
import json
import argparse
from dotenv import load_dotenv
from core.schemas import TestCase
from core.memory import GlobalSummaryMemory
from core.model_client import ModelClient
from agents.action_agent import ActionScriptAgent
from agents.verify_agent import VerifyScriptAgent
from agents.refiner_agent import RefinerAgent
from agents.persistence_agent import PersistenceAgent
from agents.coordinator_agent import CoordinatorAgent


def main():
    load_dotenv()
    
    parser = argparse.ArgumentParser(
        description="使用 CoordinatorAgent 生成增强测试用例（多 Agent 协同 + 记忆系统）"
    )
    parser.add_argument('-i', '--input', required=True, help='输入的测试用例 JSON 文件')
    parser.add_argument('-o', '--output', help='输出文件路径（默认：<input>.coordinator.json）')
    parser.add_argument('--rate-limit', type=float, default=0.5, help='API 调用间隔秒数（默认 0.5）')
    args = parser.parse_args()
    
    # 读取测试用例（支持UTF-8和UTF-16编码）
    try:
        with open(args.input, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except UnicodeDecodeError:
        # 如果UTF-8失败，尝试UTF-16
        with open(args.input, 'r', encoding='utf-16') as f:
            data = json.load(f)
    
    test_case = TestCase(**data)
    
    # 自动生成输出文件名
    if not args.output:
        input_name = args.input.replace('.json', '')
        args.output = f"{input_name}.coordinator.json"
    
    # 初始化系统
    print("🔐 使用 Azure AD 无密钥认证")
    print(f"📖 读取输入: {args.input}")
    print(f"⏱️  API 调用间隔: {args.rate_limit}秒\n")
    
    client = ModelClient()
    memory = GlobalSummaryMemory()
    
    # 创建各个 Agent
    action_agent = ActionScriptAgent(client)
    verify_agent = VerifyScriptAgent(client)
    refiner_agent = RefinerAgent()  # 静态规则，无需 ModelClient
    persistence_agent = PersistenceAgent()
    
    # 创建协调器
    coordinator = CoordinatorAgent(
        action_agent=action_agent,
        verify_agent=verify_agent,
        refiner=refiner_agent,
        persistence=persistence_agent,
        memory=memory,
        deployment=client.deployment
    )
    
    # 运行
    print("🚀 开始生成增强测试用例...\n")
    result = coordinator.run(test_case, args.output, rate_limit_sec=args.rate_limit)
    
    print(f"\n✅ 完成！已写入 {args.output}")
    print(f"   生成了 {len(result.steps)} 个步骤的脚本")
    print(f"   需要视觉验证的步骤: {sum(1 for s in result.steps if s.need_vision_verify)}")


if __name__ == '__main__':
    main()
