import os
import json
from dotenv import load_dotenv
from core.schemas import TestCase
from core.model_client import ModelClient
from core.memory import GlobalSummaryMemory
from agents.action_agent import ActionScriptAgent
from agents.verify_agent import VerifyScriptAgent
from agents.refiner_agent import RefinerAgent
from agents.persistence_agent import PersistenceAgent
from agents.coordinator_agent import CoordinatorAgent


def main():
    load_dotenv()
    import argparse
    parser = argparse.ArgumentParser(description="Multi-agent test step enrichment")
    parser.add_argument('-i', '--input', default='34717304.json')
    parser.add_argument('-o', '--output', default='outputs/34717304.enriched.json')
    parser.add_argument('--rate', type=float, default=0.5, help='Sleep seconds between steps')
    args = parser.parse_args()

    with open(args.input, 'r', encoding='utf-8') as f:
        raw = json.load(f)
    test_case = TestCase(**raw)

    model_client = ModelClient()
    memory = GlobalSummaryMemory()
    action_agent = ActionScriptAgent(model_client)
    verify_agent = VerifyScriptAgent(model_client)
    refiner = RefinerAgent()
    persistence = PersistenceAgent()
    coordinator = CoordinatorAgent(action_agent, verify_agent, refiner, persistence, memory, model_client.deployment)

    enriched = coordinator.run(test_case, args.output, rate_limit_sec=args.rate)
    print(f"Wrote {args.output} with {len(enriched.steps)} steps")


if __name__ == '__main__':
    main()
