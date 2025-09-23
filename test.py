import os
import asyncio
from dotenv import load_dotenv
from autogen_agentchat.agents import AssistantAgent
from autogen_ext.models.openai import (
    OpenAIChatCompletionClient,
    AzureOpenAIChatCompletionClient,
)

load_dotenv()  # loads variables from a .env file if present

USE_AZURE = bool(os.getenv("AZURE_OPENAI_ENDPOINT"))

def build_client():
    if USE_AZURE:
        required = [
            "AZURE_OPENAI_API_KEY",
            "AZURE_OPENAI_ENDPOINT",
            "AZURE_OPENAI_API_VERSION",
            "AZURE_OPENAI_DEPLOYMENT",  # Azure deployment name
        ]
        missing = [k for k in required if not os.getenv(k)]
        if missing:
            raise SystemExit(f"缺少 Azure 环境变量: {', '.join(missing)}")

        # The underlying client also needs a valid OpenAI model name (e.g., gpt-4o, gpt-4o-mini)
        # because your deployment name (AZURE_OPENAI_DEPLOYMENT) may be custom.
        # Allow user to specify AZURE_OPENAI_MODEL; if absent, fall back to deployment (may fail if not standard).
        azure_model = os.getenv("AZURE_OPENAI_MODEL") or os.getenv("AZURE_OPENAI_DEPLOYMENT")

        return AzureOpenAIChatCompletionClient(
            model=azure_model,
            azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
            azure_deployment=os.getenv("AZURE_OPENAI_DEPLOYMENT"),
            api_version=os.getenv("AZURE_OPENAI_API_VERSION"),
            api_key=os.getenv("AZURE_OPENAI_API_KEY"),
        )
    # Standard OpenAI path
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY 未设置，也未提供 AZURE_OPENAI_* 变量。")
    return OpenAIChatCompletionClient(
        model="gpt-4.1",
        api_key=os.getenv("OPENAI_API_KEY"),
    )

async def main() -> None:
    model_client = build_client()
    agent = AssistantAgent("assistant", model_client=model_client)
    result = await agent.run(task="Say 'Hello World!'")
    print(result)
    await model_client.close()

asyncio.run(main())