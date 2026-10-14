from types import SimpleNamespace

import anthropic

from recrutador import llm

TOOL = {"name": "t", "input_schema": {"type": "object"}}


class FakeClient:
    """Recusa ferramenta forçada (como o Sonnet) e responde com a ferramenta no modo auto."""

    def __init__(self):
        self.calls = []
        self.messages = SimpleNamespace(create=self.create)

    def create(self, **kw):
        self.calls.append(kw["tool_choice"]["type"])
        if kw["tool_choice"]["type"] == "tool":
            raise _bad_request('tool_choice: type "tool" and "any" are not supported for this model.')
        return SimpleNamespace(content=[SimpleNamespace(type="tool_use", name="t", input={"ok": True})])


def _bad_request(message):
    err = anthropic.BadRequestError.__new__(anthropic.BadRequestError)
    Exception.__init__(err, message)
    return err


def test_falls_back_to_auto_and_remembers_model():
    llm._NO_FORCED_TOOL.clear()
    c = FakeClient()
    assert llm.call_tool(c, model="m1", system="s", tool=TOOL, messages=[], max_tokens=10) == {"ok": True}
    assert llm.call_tool(c, model="m1", system="s", tool=TOOL, messages=[], max_tokens=10) == {"ok": True}
    assert c.calls == ["tool", "auto", "auto"]  # na segunda chamada já vai direto para o auto


def test_missing_tool_use_raises():
    try:
        llm._tool_input(SimpleNamespace(content=[SimpleNamespace(type="text")]), "t")
    except ValueError:
        return
    raise AssertionError("deveria levantar ValueError")
