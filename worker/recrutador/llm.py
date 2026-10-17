"""Chamada de IA com resposta estruturada (ferramenta), no provedor que o usuário escolheu no app.

Cada usuário cadastra no app o provedor (Claude/Anthropic ou ChatGPT/OpenAI), o modelo e a própria
chave. As funções de triagem, match e leitura de currículo montam as mensagens no formato da
Anthropic (blocos de texto e de PDF); para a OpenAI elas são convertidas aqui.

Alguns modelos da Anthropic não aceitam forçar a ferramenta (tool_choice "tool"). Para eles, a
chamada é refeita com tool_choice "auto" e a exigência vai nas instruções; o modelo fica lembrado
para as próximas chamadas da rodada.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field

import anthropic
import httpx

log = logging.getLogger(__name__)

PROVIDERS = ("anthropic", "openai")
OPENAI_URL = "https://api.openai.com/v1/chat/completions"

_NO_FORCED_TOOL: set[str] = set()


class AIError(Exception):
    """Falha na chamada ao provedor de IA (rede, limite, resposta inválida)."""


class AIAuthError(AIError):
    """Chave recusada ou sem crédito: não adianta tentar as outras vagas com ela."""


@dataclass
class AIClient:
    provider: str
    model: str
    api_key: str = field(repr=False)
    contact_email: str = ""
    client: object | None = None  # injetável nos testes

    def __post_init__(self) -> None:
        if self.provider not in PROVIDERS:
            raise ValueError(f"provedor de IA desconhecido: {self.provider}")
        if self.client is None:
            self.client = (anthropic.Anthropic(api_key=self.api_key) if self.provider == "anthropic"
                           else httpx.Client(timeout=120))

    @property
    def label(self) -> str:
        return f"{'Claude' if self.provider == 'anthropic' else 'ChatGPT'} {self.model}"

    def call_tool(self, *, system: str, tool: dict, messages: list, max_tokens: int) -> dict:
        """Devolve os argumentos da chamada à ferramenta. Levanta AIError (ou AIAuthError)."""
        if self.provider == "anthropic":
            return self._anthropic(system, tool, messages, max_tokens)
        return self._openai(system, tool, messages, max_tokens)

    # ---------- Anthropic ----------

    def _anthropic(self, system: str, tool: dict, messages: list, max_tokens: int) -> dict:
        name, model, client = tool["name"], self.model, self.client
        try:
            if model not in _NO_FORCED_TOOL:
                try:
                    msg = client.messages.create(model=model, max_tokens=max_tokens, system=system, tools=[tool],
                                                 tool_choice={"type": "tool", "name": name}, messages=messages)
                    return _tool_input(msg, name)
                except anthropic.BadRequestError as exc:
                    if "tool_choice" not in str(exc):
                        raise
                    log.info("modelo %s não aceita ferramenta forçada; usando tool_choice auto", model)
                    _NO_FORCED_TOOL.add(model)
            msg = client.messages.create(
                model=model, max_tokens=max_tokens, tools=[tool], tool_choice={"type": "auto"}, messages=messages,
                system=f"{system}\n\nResponda SEMPRE chamando a ferramenta {name}, sem texto antes ou depois.",
            )
            return _tool_input(msg, name)
        except (anthropic.AuthenticationError, anthropic.PermissionDeniedError) as exc:
            raise AIAuthError(f"chave da Anthropic recusada: {exc}") from exc
        except anthropic.APIError as exc:
            if "credit balance" in str(exc).lower():
                raise AIAuthError(f"sem crédito na Anthropic: {exc}") from exc
            raise AIError(str(exc)) from exc

    # ---------- OpenAI ----------

    def _openai(self, system: str, tool: dict, messages: list, max_tokens: int) -> dict:
        name = tool["name"]
        body = {
            "model": self.model,
            "messages": [{"role": "system", "content": system}, *[to_openai_message(m) for m in messages]],
            "tools": [{"type": "function", "function": {
                "name": name, "description": tool.get("description", ""), "parameters": tool["input_schema"]}}],
            "tool_choice": {"type": "function", "function": {"name": name}},
            # modelos com raciocínio contam o "pensamento" neste limite: dá folga
            "max_completion_tokens": max(max_tokens * 4, 2000),
        }
        try:
            resp = self.client.post(OPENAI_URL, json=body, headers={"Authorization": f"Bearer {self.api_key}"})
        except httpx.HTTPError as exc:
            raise AIError(f"OpenAI inacessível: {exc}") from exc
        if resp.status_code in (401, 403) or (resp.status_code == 429 and "insufficient_quota" in resp.text):
            raise AIAuthError(f"chave da OpenAI recusada ou sem crédito ({resp.status_code}): {resp.text[:300]}")
        if resp.status_code >= 400:
            raise AIError(f"OpenAI respondeu {resp.status_code}: {resp.text[:300]}")
        try:
            message = resp.json()["choices"][0]["message"]
            for call in message.get("tool_calls") or []:
                if call["function"]["name"] == name:
                    return json.loads(call["function"]["arguments"])
        except (KeyError, IndexError, ValueError) as exc:
            raise AIError(f"resposta inesperada da OpenAI: {exc}") from exc
        raise AIError(f"o modelo não chamou a ferramenta {name}")


def to_openai_message(message: dict) -> dict:
    """Converte uma mensagem no formato da Anthropic (texto e PDFs em base64) para a OpenAI."""
    content = message["content"]
    if isinstance(content, str):
        return {"role": message["role"], "content": content}
    parts = []
    for block in content:
        if block["type"] == "text":
            parts.append({"type": "text", "text": block["text"]})
        elif block["type"] == "document":
            src = block["source"]
            parts.append({"type": "file", "file": {
                "filename": f"{block.get('title') or 'documento'}.pdf",
                "file_data": f"data:{src['media_type']};base64,{src['data']}"}})
        # cache_control é só da Anthropic; a OpenAI faz cache automático
    return {"role": message["role"], "content": parts}


def _tool_input(msg, name: str) -> dict:
    for block in msg.content:
        if block.type == "tool_use" and block.name == name:
            return block.input
    raise AIError(f"o modelo não chamou a ferramenta {name}")
