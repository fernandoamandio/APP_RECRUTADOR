"""Lê o currículo em PDF (arquivo próprio ou PDF exportado do LinkedIn) e a cover letter com a IA do usuário
e devolve o perfil profissional que alimenta a busca, a pontuação e o match.
"""

from __future__ import annotations

import base64

from .llm import AIClient

PROFILE_TOOL = {
    "name": "save_career_profile",
    "description": "Salva o perfil profissional extraído do currículo.",
    "input_schema": {
        "type": "object",
        "properties": {
            "target_titles": {"type": "array", "items": {"type": "string"}, "maxItems": 8,
                              "description": "Cargos-alvo e variações de título em inglês e português, mais prováveis primeiro."},
            "seniority": {"type": "string", "enum": ["junior", "mid", "senior", "staff", "lead", "manager"]},
            "years_total": {"type": ["number", "null"], "description": "Anos de experiência na área, se dedutível."},
            "stack": {"type": "array", "items": {"type": "object", "properties": {
                "name": {"type": "string"},
                "level": {"type": "string", "enum": ["main", "secondary", "basic"]},
                "years": {"type": ["number", "null"]},
            }, "required": ["name", "level"]}},
            "domains": {"type": "array", "items": {"type": "string"}, "description": "Domínios de negócio (saúde, finanças...)."},
            "languages": {"type": "array", "items": {"type": "object", "properties": {
                "language": {"type": "string"},
                "level": {"type": "string", "enum": ["basic", "intermediate", "advanced", "fluent", "native"]},
            }, "required": ["language", "level"]}},
            "search_terms": {"type": "array", "items": {"type": "string"}, "maxItems": 6,
                             "description": "Termos de busca em inglês para sites de vagas (ex.: 'PL/SQL Developer')."},
            "remoteok_tags": {"type": "array", "items": {"type": "string"}, "maxItems": 6,
                              "description": "Tags curtas em minúsculas (ex.: oracle, sql, plsql)."},
            "strengths": {"type": "array", "items": {"type": "string"}, "maxItems": 4,
                          "description": "Pontos fortes para o mercado internacional, em português."},
            "gaps": {"type": "array", "items": {"type": "string"}, "maxItems": 4,
                     "description": "Lacunas do currículo com sugestão concreta de melhoria, em português."},
        },
        "required": ["target_titles", "seniority", "stack", "search_terms", "remoteok_tags", "strengths", "gaps"],
    },
}

SYSTEM = (
    "Você analisa currículos de profissionais brasileiros que buscam vagas no Brasil, remotas para empresas "
    "estrangeiras ou com patrocínio de visto. O currículo pode ser um PDF exportado do perfil do LinkedIn. "
    "Extraia apenas o que está no documento; não invente empresas, anos, certificações ou números. "
    "Use a cover letter, se houver, só para entender motivações e tom. Responda chamando save_career_profile."
)


def _pdf_block(title: str, pdf: bytes) -> dict:
    return {"type": "document", "title": title,
            "source": {"type": "base64", "media_type": "application/pdf",
                       "data": base64.standard_b64encode(pdf).decode()}}


def extract_profile(ai: AIClient, cv_pdf: bytes,
                    cover_letter_pdf: bytes | None = None) -> dict:
    content = [_pdf_block("Currículo", cv_pdf)]
    if cover_letter_pdf:
        content.append(_pdf_block("Cover letter", cover_letter_pdf))
    content.append({"type": "text", "text": "Extraia o perfil profissional destes documentos."})
    return ai.call_tool(system=SYSTEM, tool=PROFILE_TOOL,
                     messages=[{"role": "user", "content": content}], max_tokens=2048)


def to_career_profile_row(user_id: str, doc_id: str, p: dict) -> dict:
    """Converte a saída da IA na linha de career_profile."""
    return {
        "user_id": user_id,
        "target_titles": p.get("target_titles") or [],
        "seniority": p.get("seniority"),
        "years_total": p.get("years_total"),
        "stack": p.get("stack") or [],
        "domains": p.get("domains") or [],
        "keywords": {"search_terms": p.get("search_terms") or [], "remoteok_tags": p.get("remoteok_tags") or []},
        "strengths": p.get("strengths") or [],
        "gaps": p.get("gaps") or [],
        "source_doc_id": doc_id,
    }
