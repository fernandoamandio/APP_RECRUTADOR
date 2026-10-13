from __future__ import annotations

from datetime import datetime, timezone

import httpx

from ..models import RawJob
from .base import JobSource, specific_words, strip_html

BASE_URL = "https://www.arbeitnow.com/api/job-board-api"
VISA_NOTE = "[Fonte Arbeitnow: vaga marcada com patrocínio de visto disponível]"


class ArbeitnowSource(JobSource):
    """API pública e gratuita da Arbeitnow (vagas na Europa, forte na Alemanha), sem chave.

    Buscamos as vagas marcadas com patrocínio de visto e as gerais, e filtramos pelos
    termos do perfil localmente (a API não tem busca por palavra-chave).
    """

    name = "arbeitnow"

    def __init__(self, client: httpx.Client, visa_pages: int = 3, general_pages: int = 2):
        super().__init__(client)
        self.visa_pages, self.general_pages = visa_pages, general_pages

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for visa, pages in ((True, self.visa_pages), (False, self.general_pages)):
            for page in range(1, pages + 1):
                params = {"page": page}
                if visa:
                    params["visa_sponsorship"] = "true"
                resp = self.client.get(BASE_URL, params=params)
                resp.raise_for_status()
                batch = self.parse(resp.json(), search_terms + tags, visa=visa)
                jobs.extend(batch)
                if not resp.json().get("data"):
                    break
        return jobs

    @staticmethod
    def parse(payload: dict, keywords: list[str], visa: bool = False) -> list[RawJob]:
        words = specific_words(keywords)
        out = []
        for j in payload.get("data", []):
            title = j.get("title", "")
            description = strip_html(j.get("description"))
            text = f"{title} {' '.join(j.get('tags', []))} {description}".lower()
            if words and not any(w in text for w in words):
                continue
            if visa:
                description = f"{VISA_NOTE}\n{description}"
            created = j.get("created_at")
            out.append(RawJob(
                source="arbeitnow",
                external_id=j["slug"],
                url=j.get("url", ""),
                title=title.strip(),
                company=(j.get("company_name") or "").strip(),
                description=description,
                city=j.get("location") or None,
                is_remote=bool(j.get("remote")),
                published_at=datetime.fromtimestamp(created, tz=timezone.utc) if created else None,
                tags=[t.lower() for t in j.get("tags", [])],
            ))
        return out
