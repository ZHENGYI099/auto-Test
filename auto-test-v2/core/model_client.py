"""
Azure OpenAI Model Client
使用 Azure AD 认证的 OpenAI 客户端
"""
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from .retry import retry

class ModelClient:
    """Azure OpenAI Client with Azure AD Authentication"""
    
    def __init__(self):
        # 从环境变量读取配置
        endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        api_version = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
        self.deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")
        
        if not endpoint:
            raise RuntimeError("AZURE_OPENAI_ENDPOINT environment variable missing")
        
        # 使用无密钥认证（Azure AD Token）
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://cognitiveservices.azure.com/.default"
        )
        
        # 初始化客户端
        self._client = AzureOpenAI(
            azure_endpoint=endpoint,
            api_version=api_version,
            azure_ad_token_provider=token_provider
        )
    
    def generate(self, system_prompt: str, user_prompt: str, temperature: float = 0.3, max_tokens: int = 16000) -> str:
        """
        Generate response from Azure OpenAI
        
        Args:
            system_prompt: System instruction
            user_prompt: User query
            temperature: Response randomness (0.0-1.0)
            max_tokens: Maximum tokens to generate (default 16000 - maximum for GPT-4)
        
        Returns:
            Generated text
        """
        def _call():
            resp = self._client.chat.completions.create(
                model=self.deployment,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=temperature,
                max_tokens=max_tokens
            )
            content = resp.choices[0].message.content.strip()
            # Remove markdown code fences if present
            if content.startswith("```"):
                lines = content.splitlines()
                if len(lines) >= 2 and lines[-1].startswith("```"):
                    return "\n".join(lines[1:-1]).strip()
            return content
        
        return retry(_call)
    
    def generate_with_context(self, messages: list, temperature: float = 0.3, max_tokens: int = 16000) -> str:
        """
        Generate with conversation context
        
        Args:
            messages: List of {"role": "...", "content": "..."} dicts
            temperature: Response randomness
            max_tokens: Maximum tokens to generate (default 16000 - maximum for GPT-4)
        
        Returns:
            Generated text
        """
        def _call():
            resp = self._client.chat.completions.create(
                model=self.deployment,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens
            )
            content = resp.choices[0].message.content.strip()
            # Remove markdown code fences if present
            if content.startswith("```"):
                lines = content.splitlines()
                if len(lines) >= 2 and lines[-1].startswith("```"):
                    return "\n".join(lines[1:-1]).strip()
            return content
        
        return retry(_call)
