from __future__ import annotations

import html
import logging
import re
from abc import ABC, abstractmethod

import httpx

from ..models import RawJob

log = logging.getLogger(__name__)

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


# Palavras genéricas de título que não dizem nada sobre a especialidade
GENERIC_WORDS = {"developer", "engineer", "senior", "junior", "lead", "staff", "principal", "remote",
                 "software", "programmer", "analyst", "specialist", "consultant", "the", "and", "for"}


def specific_words(terms: list[str]) -> set[str]:
    """Palavras distintivas dos termos de busca (ex.: 'PL/SQL Developer' -> {'pl/sql'})."""
    return {w for t in terms for w in t.lower().split() if len(w) > 2 and w not in GENERIC_WORDS}


def strip_html(text: str | None) -> str:
    if not text:
        return ""
    return _WS_RE.sub(" ", html.unescape(_TAG_RE.sub(" ", text))).strip()


class JobSource(ABC):
    """Uma fonte de vagas. Cada fonte isola formato, autenticação e regras de atribuição."""

    name: str

    def __init__(self, client: httpx.Client):
        self.client = client

    @abstractmethod
    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        """Retorna vagas normalizadas. Nunca deve levantar exceção por falha da fonte."""

    def safe_fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        try:
            jobs = self.fetch(search_terms, tags)
            log.info("%s: %d vagas", self.name, len(jobs))
            return jobs
        except httpx.HTTPError as exc:  # uma fonte fora do ar não derruba a rodada
            log.warning("%s indisponível: %s", self.name, exc)
            return []
