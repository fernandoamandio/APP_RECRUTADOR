"""Deduplicação: mesma empresa + título normalizado + país = uma vaga só."""

from __future__ import annotations

import hashlib
import re
import unicodedata

from .models import RawJob

_COMPANY_SUFFIXES = re.compile(
    r"\b(inc|incorporated|ltd|limited|llc|plc|gmbh|ag|bv|b\.v|nv|sa|s\.a|ltda|corp|corporation|co|company|group|holding|holdings)\b\.?",
    re.I,
)
_SENIORITY_NOISE = re.compile(r"\b(m/f/d|m/w/d|f/m/d|h/f|remote|remoto|hybrid|full[- ]time)\b", re.I)
_NON_ALNUM = re.compile(r"[^a-z0-9]+")


def _ascii(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()


def normalize_company(name: str) -> str:
    text = _COMPANY_SUFFIXES.sub(" ", _ascii(name))
    return _NON_ALNUM.sub(" ", text).strip()


def normalize_title(title: str) -> str:
    text = _SENIORITY_NOISE.sub(" ", _ascii(title))
    text = re.sub(r"\(.*?\)", " ", text)
    text = text.replace("sr.", "senior").replace("sr ", "senior ")
    return _NON_ALNUM.sub(" ", text).strip()


def dedup_hash(job: RawJob) -> str:
    key = "|".join([normalize_company(job.company), normalize_title(job.title), (job.country or "remote").upper()])
    return hashlib.sha256(key.encode()).hexdigest()


def deduplicate(jobs: list[RawJob]) -> dict[str, list[RawJob]]:
    """Agrupa vagas iguais vindas de fontes diferentes. Chave = dedup_hash."""
    groups: dict[str, list[RawJob]] = {}
    seen: set[tuple[str, str]] = set()
    for job in jobs:
        if not job.title or not job.company:
            continue
        # A mesma vaga pode voltar da mesma fonte por termos de busca diferentes
        key = (job.source, job.external_id)
        if key in seen:
            continue
        seen.add(key)
        groups.setdefault(dedup_hash(job), []).append(job)
    return groups


def merge(group: list[RawJob]) -> RawJob:
    """Escolhe a versão mais completa (descrição mais longa) e completa salário/país das demais."""
    best = max(group, key=lambda j: len(j.description))
    for other in group:
        if best.salary_min is None and other.salary_min is not None:
            best.salary_min, best.salary_max = other.salary_min, other.salary_max
            best.salary_period, best.currency = other.salary_period, other.currency
        if best.country is None and other.country:
            best.country = other.country
        if best.is_remote is None and other.is_remote is not None:
            best.is_remote = other.is_remote
    return best
