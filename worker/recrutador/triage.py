"""Triagem de elegibilidade com o Claude: a vaga serve para quem está no Brasil?

Cada vaga é classificada UMA vez e o resultado é compartilhado entre todos os usuários.
"""

from __future__ import annotations

import logging

import anthropic

from .models import Eligibility, RawJob, TriageResult
from .sponsors import SponsorRegistry

log = logging.getLogger(__name__)

MAX_DESCRIPTION_CHARS = 12_000

TRIAGE_TOOL = {
    "name": "classify_job",
    "description": "Registra se a vaga é viável para um profissional que mora no Brasil.",
    "input_schema": {
        "type": "object",
        "properties": {
            "category": {
                "type": "string",
                "enum": [e.value for e in Eligibility],
                "description": (
                    "remote_br: remota e aceita Brasil, LATAM, 'anywhere' ou contractor internacional; "
                    "visa_sponsor: presencial/híbrida com patrocínio de visto ou relocation oferecidos; "
                    "uncertain: remota sem restrição clara de país, ou patrocínio não mencionado; "
                    "not_eligible: restrição de país, cidadania, fuso inviável ou 'no sponsorship'."
                ),
            },
            "evidence": {
                "type": "string",
                "description": "Trecho literal e curto (até 25 palavras) da vaga que justifica a categoria. Vazio se não houver.",
            },
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        },
        "required": ["category", "evidence", "confidence"],
    },
}

SYSTEM = (
    "Você classifica vagas de emprego para candidatos que moram no Brasil. "
    "Baseie-se apenas no texto da vaga. Não presuma patrocínio ou aceitação do Brasil sem evidência. "
    "Responda chamando a ferramenta classify_job."
)


def _job_prompt(job: RawJob) -> str:
    location = ", ".join(filter(None, [job.city, job.country])) or "não informado"
    remote = {True: "sim", False: "não", None: "não informado"}[job.is_remote]
    return (
        f"Título: {job.title}\nEmpresa: {job.company}\nLocal: {location}\nRemota (segundo a fonte): {remote}\n\n"
        f"Descrição:\n{job.description[:MAX_DESCRIPTION_CHARS]}"
    )


def triage(client: anthropic.Anthropic, model: str, job: RawJob, sponsors: SponsorRegistry) -> TriageResult:
    registered = sponsors.is_registered(job.company, job.country)
    msg = client.messages.create(
        model=model,
        max_tokens=400,
        system=SYSTEM,
        tools=[TRIAGE_TOOL],
        tool_choice={"type": "tool", "name": "classify_job"},
        messages=[{"role": "user", "content": _job_prompt(job)}],
    )
    data = next(b.input for b in msg.content if b.type == "tool_use")
    category = Eligibility(data["category"])

    # Registro oficial reforça uma vaga presencial "incerta" como possível patrocínio
    if registered and category is Eligibility.UNCERTAIN and job.is_remote is False:
        category = Eligibility.VISA_SPONSOR

    return TriageResult(
        category=category,
        evidence=data.get("evidence", "")[:400],
        confidence=float(data.get("confidence", 0.5)),
        sponsor_registered=registered,
        model=model,
    )
