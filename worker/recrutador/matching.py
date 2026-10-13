"""Percentual de match entre o candidato (currículo + cover letter) e cada vaga, calculado pelo Claude.

O currículo e a cover letter vão em todas as chamadas do mesmo usuário, então ficam
num bloco com cache de prompt: só a primeira chamada paga o preço cheio desses documentos.
Sem documentos enviados, usa o perfil profissional salvo (career_profile) como texto.
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field

import anthropic

from .models import RawJob

MAX_JOB_CHARS = 8_000

MATCH_TOOL = {
    "name": "record_match",
    "description": "Registra o quanto o candidato atende à vaga.",
    "input_schema": {
        "type": "object",
        "properties": {
            "match_percent": {
                "type": "integer", "minimum": 0, "maximum": 100,
                "description": (
                    "Aderência do candidato aos requisitos da vaga. 90+: atende a todos os obrigatórios e à maioria "
                    "dos desejáveis; 70-89: atende aos obrigatórios com poucas lacunas; 50-69: lacunas relevantes; "
                    "abaixo de 50: falta requisito obrigatório central (stack, senioridade ou idioma)."
                ),
            },
            "strengths": {"type": "array", "items": {"type": "string"}, "maxItems": 3,
                          "description": "Até 3 pontos do candidato que atendem à vaga, curtos, em português."},
            "gaps": {"type": "array", "items": {"type": "string"}, "maxItems": 3,
                     "description": "Até 3 requisitos da vaga que o candidato não demonstra, curtos, em português."},
        },
        "required": ["match_percent", "strengths", "gaps"],
    },
}

SYSTEM = (
    "Você compara o perfil de um candidato com uma vaga de emprego. Baseie-se apenas no que está nos "
    "documentos do candidato e no texto da vaga; não presuma experiências que não aparecem. "
    "A elegibilidade geográfica já foi avaliada antes: avalie só a aderência técnica e profissional. "
    "Responda chamando a ferramenta record_match."
)


@dataclass
class CandidateMaterial:
    """O que o Claude recebe sobre o candidato: PDFs (preferência) ou o perfil em texto."""

    cv_pdf: bytes | None = None
    cover_letter_pdf: bytes | None = None
    profile_text: str = ""

    @property
    def source(self) -> str:
        if self.cv_pdf:
            return "cv+cover_letter" if self.cover_letter_pdf else "cv"
        return "profile"

    def content_blocks(self) -> list[dict]:
        blocks: list[dict] = []
        for title, pdf in (("Currículo", self.cv_pdf), ("Cover letter", self.cover_letter_pdf)):
            if pdf:
                blocks.append({"type": "document", "title": title, "source": {
                    "type": "base64", "media_type": "application/pdf",
                    "data": base64.standard_b64encode(pdf).decode()}})
        if not blocks:
            blocks.append({"type": "text", "text": f"Perfil profissional do candidato:\n{self.profile_text}"})
        # Cache de prompt: tudo até aqui se repete em todas as vagas do mesmo usuário
        blocks[-1]["cache_control"] = {"type": "ephemeral"}
        return blocks


@dataclass
class MatchResult:
    percent: int
    strengths: list[str] = field(default_factory=list)
    gaps: list[str] = field(default_factory=list)


def profile_as_text(profile_row: dict) -> str:
    keep = ("target_titles", "seniority", "years_total", "stack", "domains", "strengths")
    return json.dumps({k: profile_row.get(k) for k in keep if profile_row.get(k)}, ensure_ascii=False)


def job_as_text(job: RawJob) -> str:
    location = ", ".join(filter(None, [job.city, job.country])) or "não informado"
    return f"VAGA\nTítulo: {job.title}\nEmpresa: {job.company}\nLocal: {location}\n\n{job.description[:MAX_JOB_CHARS]}"


def parse_match(data: dict) -> MatchResult:
    pct = max(0, min(100, int(round(float(data.get("match_percent", 0))))))
    clean = lambda xs: [str(x).strip()[:160] for x in (xs or []) if str(x).strip()][:3]  # noqa: E731
    return MatchResult(percent=pct, strengths=clean(data.get("strengths")), gaps=clean(data.get("gaps")))


def match(client: anthropic.Anthropic, model: str, candidate: CandidateMaterial, job: RawJob) -> MatchResult:
    msg = client.messages.create(
        model=model,
        max_tokens=600,
        system=SYSTEM,
        tools=[MATCH_TOOL],
        tool_choice={"type": "tool", "name": "record_match"},
        messages=[{"role": "user", "content": [
            *candidate.content_blocks(),
            {"type": "text", "text": job_as_text(job)},
        ]}],
    )
    return parse_match(next(b.input for b in msg.content if b.type == "tool_use"))
