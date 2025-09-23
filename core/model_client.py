import os
from openai import AzureOpenAI
from .retry import retry

class ModelClient:
    def __init__(self):
        endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        key = os.getenv("AZURE_OPENAI_API_KEY")
        api_version = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
        if not endpoint or not key:
            raise RuntimeError("Azure OpenAI credentials missing")
        self.deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")
        self._client = AzureOpenAI(azure_endpoint=endpoint, api_key=key, api_version=api_version)

    def chat(self, system: str, user: str, max_tokens: int = 300, temperature: float = 0.0) -> str:
        def _call():
            resp = self._client.chat.completions.create(
                model=self.deployment,
                messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
                temperature=temperature,
                max_tokens=max_tokens
            )
            content = resp.choices[0].message.content.strip()
            if content.startswith("```"):
                lines = content.splitlines()
                if len(lines) >= 2 and lines[-1].startswith("```"):
                    return "\n".join(lines[1:-1]).strip()
            return content
        return retry(_call)

    def chat_messages(self, messages, max_tokens: int = 300, temperature: float = 0.0) -> str:
        """Generic chat interface allowing rich content (e.g., image_url).

        messages: list of dicts, each like {"role": "user"|"system"|"assistant", "content": <str|list>}
        If any content is a list (multi-part), it is passed through directly.
        """
        def _call():
            resp = self._client.chat.completions.create(
                model=self.deployment,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens
            )
            content = resp.choices[0].message.content.strip()
            if content.startswith("```"):
                lines = content.splitlines()
                if len(lines) >= 2 and lines[-1].startswith("```"):
                    return "\n".join(lines[1:-1]).strip()
            return content
        return retry(_call)
