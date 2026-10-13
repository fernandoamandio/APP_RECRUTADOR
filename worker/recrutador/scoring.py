"""Nota de aderência (0–100) de uma vaga ao perfil do usuário.

Heurística barata e explicável para o MVP; aplica os ajustes aprendidos com o feedback.
"""

from __future__ import annotations

import re

from .dedup import normalize_company, normalize_title
from .models import CareerProfile, Eligibility, RawJob

STACK_WEIGHT = {"main": 1.0, "secondary": 0.5, "basic": 0.2}
SENIORITY_WORDS = {
    "junior": ["junior", "jr"], "mid": ["mid", "pleno", "intermediate"],
    "senior": ["senior", "sr", "sênior"], "staff": ["staff", "principal"],
    "lead": ["lead", "tech lead"], "manager": ["manager", "head"],
}


def _contains(text: str, term: str) -> bool:
    return re.search(rf"(?<![a-z0-9]){re.escape(term.lower())}(?![a-z0-9])", text) is not None


def score(job: RawJob, profile: CareerProfile, eligibility: Eligibility,
          learned: dict[str, float] | None = None) -> tuple[int, list[str]]:
    learned = learned or {}
    title = normalize_title(job.title)
    text = f"{title} {job.description.lower()}"
    reasons: list[str] = []
    points = 0.0

    # Título: até 40
    best_title = max((len(set(normalize_title(t).split()) & set(title.split())) / max(len(normalize_title(t).split()), 1)
                      for t in profile.target_titles), default=0)
    points += 40 * best_title
    if best_title >= 0.66:
        reasons.append("Título alinhado ao seu cargo-alvo")

    # Stack: até 40
    total_w = sum(STACK_WEIGHT.get(s.get("level", "basic"), 0.2) for s in profile.stack) or 1
    hit = [s["name"] for s in profile.stack if _contains(text, s["name"])]
    hit_w = sum(STACK_WEIGHT.get(s.get("level", "basic"), 0.2) for s in profile.stack if s["name"] in hit)
    points += 40 * min(hit_w / total_w * 1.5, 1)
    if hit:
        reasons.append("Pede " + ", ".join(hit[:3]))

    # Senioridade: até 10
    if profile.seniority and any(_contains(title, w) for w in SENIORITY_WORDS.get(profile.seniority, [])):
        points += 10
        reasons.append("Senioridade compatível")
    elif not any(_contains(title, w) for ws in SENIORITY_WORDS.values() for w in ws):
        points += 5  # título sem senioridade explícita

    # Elegibilidade: até 10
    points += {Eligibility.LOCAL_BR: 10, Eligibility.REMOTE_BR: 10, Eligibility.VISA_SPONSOR: 10,
               Eligibility.UNCERTAIN: 3}.get(eligibility, 0)

    # Ajustes aprendidos (pesos em pontos, positivos ou negativos)
    points += learned.get(f"company:{normalize_company(job.company)}", 0)
    if job.country:
        points += learned.get(f"country:{job.country.upper()}", 0)

    return max(0, min(100, round(points))), reasons[:3]
