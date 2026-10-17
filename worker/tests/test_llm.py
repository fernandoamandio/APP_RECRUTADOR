import base64
import json
from types import SimpleNamespace

import anthropic

from recrutador import llm
from recrutador.llm import AIClient, AIAuthError, AIError

TOOL = {"name": "t", "description": "d", "input_schema": {"type": "object"}}


class FakeAnthropic:
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


def test_anthropic_falls_back_to_auto_and_remembers_model():
    llm._NO_FORCED_TOOL.clear()
    c = FakeAnthropic()
    ai = AIClient("anthropic", "m1", "k", client=c)
    assert ai.call_tool(system="s", tool=TOOL, messages=[], max_tokens=10) == {"ok": True}
    assert ai.call_tool(system="s", tool=TOOL, messages=[], max_tokens=10) == {"ok": True}
    assert c.calls == ["tool", "auto", "auto"]  # na segunda chamada já vai direto para o auto


def test_missing_tool_use_raises():
    try:
        llm._tool_input(SimpleNamespace(content=[SimpleNamespace(type="text")]), "t")
    except AIError:
        return
    raise AssertionError("deveria levantar AIError")


class FakeHTTP:
    def __init__(self, status=200, payload=None, text=""):
        self.status, self.payload, self.text, self.sent = status, payload, text, None

    def post(self, url, json=None, headers=None):
        self.sent = (url, json, headers)
        return SimpleNamespace(status_code=self.status, text=self.text, json=lambda: self.payload)


def test_openai_tool_call_and_pdf_conversion():
    payload = {"choices": [{"message": {"tool_calls": [
        {"function": {"name": "t", "arguments": json.dumps({"match_percent": 80})}}]}}]}
    http = FakeHTTP(payload=payload)
    ai = AIClient("openai", "gpt-x", "sk-1", client=http)
    pdf = base64.standard_b64encode(b"%PDF").decode()
    messages = [{"role": "user", "content": [
        {"type": "document", "title": "Currículo",
         "source": {"type": "base64", "media_type": "application/pdf", "data": pdf}},
        {"type": "text", "text": "vaga", "cache_control": {"type": "ephemeral"}}]}]
    assert ai.call_tool(system="s", tool=TOOL, messages=messages, max_tokens=100) == {"match_percent": 80}
    url, body, headers = http.sent
    assert headers["Authorization"] == "Bearer sk-1" and body["model"] == "gpt-x"
    assert body["tool_choice"]["function"]["name"] == "t"
    assert body["messages"][0] == {"role": "system", "content": "s"}
    file_part, text_part = body["messages"][1]["content"]
    assert file_part["file"]["filename"] == "Currículo.pdf"
    assert file_part["file"]["file_data"].startswith("data:application/pdf;base64,")
    assert text_part == {"type": "text", "text": "vaga"}


def test_openai_bad_key_is_auth_error():
    ai = AIClient("openai", "gpt-x", "sk-bad", client=FakeHTTP(status=401, text="invalid_api_key"))
    try:
        ai.call_tool(system="s", tool=TOOL, messages=[], max_tokens=10)
    except AIAuthError:
        return
    raise AssertionError("deveria levantar AIAuthError")
