"""Pré-filtro barato: descarta vagas claramente inelegíveis antes de gastar IA."""

from __future__ import annotations

import re

from .models import RawJob

# Restrições explícitas de localização/cidadania que excluem quem está no Brasil
_HARD_BLOCKERS = [
    r"\b(us|u\.s\.) citizens? only\b",
    r"\bmust be (a )?(us|u\.s\.|uk|eu) citizen\b",
    r"\bmust (be located|reside|live) in (the )?(us|u\.s\.|usa|united states|uk|canada)\b",
    r"\b(security|government) clearance (required|needed)\b",
    r"\bactive (secret|top secret) clearance\b",
]

# Sinais fortes de "sem patrocínio" — só bloqueiam vaga presencial; remota pode seguir
_NO_SPONSORSHIP = [
    r"\b(no|not able to|unable to|cannot|can't|will not|won't) (provide |offer )?(visa )?sponsor(ship)?\b",
    r"\bsponsorship (is )?not (available|offered|provided)\b",
    r"\bmust (already )?have (the )?right to work\b",
]

_BLOCK_RE = re.compile("|".join(_HARD_BLOCKERS), re.I)
_NOSPONSOR_RE = re.compile("|".join(_NO_SPONSORSHIP), re.I)


def prefilter(job: RawJob) -> tuple[bool, str | None]:
    """Retorna (passa, motivo_do_descarte)."""
    text = f"{job.title}\n{job.description}"
    if m := _BLOCK_RE.search(text):
        return False, f"restrição: {m.group(0)}"
    if job.is_remote is False and (m := _NOSPONSOR_RE.search(text)):
        return False, f"sem patrocínio: {m.group(0)}"
    return True, None
