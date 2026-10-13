from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class Eligibility(str, Enum):
    REMOTE_BR = "remote_br"
    VISA_SPONSOR = "visa_sponsor"
    UNCERTAIN = "uncertain"
    NOT_ELIGIBLE = "not_eligible"


@dataclass
class RawJob:
    """Vaga como veio da fonte, já normalizada para um formato comum."""

    source: str
    external_id: str
    url: str
    title: str
    company: str
    description: str = ""
    country: str | None = None  # ISO 3166-1 alpha-2, maiúsculo
    city: str | None = None
    is_remote: bool | None = None
    salary_min: float | None = None
    salary_max: float | None = None
    salary_period: str | None = None  # year | month | hour
    currency: str | None = None
    published_at: datetime | None = None
    tags: list[str] = field(default_factory=list)


@dataclass
class TriageResult:
    category: Eligibility
    evidence: str
    confidence: float
    sponsor_registered: bool = False
    model: str | None = None


@dataclass
class Household:
    married: bool = False
    children_ages: list[int] = field(default_factory=list)

    @property
    def people(self) -> int:
        return 1 + (1 if self.married else 0) + len(self.children_ages)

    @property
    def school_age_children(self) -> int:
        return sum(1 for a in self.children_ages if 4 <= a <= 17)


@dataclass
class CareerProfile:
    target_titles: list[str]
    stack: list[dict]  # [{name, level}]
    seniority: str | None = None
    search_terms: list[str] = field(default_factory=list)
    remoteok_tags: list[str] = field(default_factory=list)
