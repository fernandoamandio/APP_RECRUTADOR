"""Chamada ao Claude que exige a resposta estruturada de uma ferramenta.

Alguns modelos não aceitam forçar a ferramenta (tool_choice "tool"). Para eles, a chamada é
refeita com tool_choice "auto" e a exigência vai nas instruções; o modelo fica lembrado para
as próximas chamadas da rodada.
"""

from __future__ import annotations

import logging

import anthropic

log = logging.getLogger(__name__)

_NO_FORCED_TOOL: set[str] = set()


def call_tool(client: anthropic.Anthropic, *, model: str, system: str, tool: dict, messages: list,
              max_tokens: int) -> dict:
    """Devolve o `input` da chamada à ferramenta. Levanta ValueError se o modelo não a usar."""
    name = tool["name"]
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


def _tool_input(msg, name: str) -> dict:
    for block in msg.content:
        if block.type == "tool_use" and block.name == name:
            return block.input
    raise ValueError(f"o modelo não chamou a ferramenta {name}")
