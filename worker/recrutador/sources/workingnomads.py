from __future__ import annotations

import hashlib
from datetime import datetime

import httpx

from ..models import RawJob
from .base import JobSource, specific_words, strip_html


class WorkingNomadsSource(JobSource):
    """Feed público de vagas remotas da Working Nomads (JSON, sem chave).

    O feed não traz termos de uso; seguimos a mesma regra das demais fontes:
    o app sempre mostra a fonte e linka para a vaga na Working Nomads.
    """

    name = "workingnomads"

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        resp = self.client.get("https://www.workingnomads.com/api/exposed_jobs/")
        resp.raise_for_status()
        return self.parse(resp.json(), search_terms + tags)

    @staticmethod
    def parse(payload: list, keywords: list[str]) -> list[RawJob]:
        words = specific_words(keywords)
        out = []
        for j in payload:
            title = j.get("title", "")
            job_tags = [t.strip().lower() for t in (j.get("tags") or "").split(",") if t.strip()]
            description = strip_html(j.get("description"))
            text = f"{title} {' '.join(job_tags)} {description}".lower()
            if words and not any(w in text for w in words):
                continue
            url = j.get("url", "")
            pub = j.get("pub_date")
            out.append(RawJob(
                source="workingnomads",
                external_id=url.rstrip("/").rsplit("/", 1)[-1] or hashlib.sha1(url.encode()).hexdigest(),
                url=url,
                title=title.strip(),
                company=(j.get("company_name") or "").strip(),
                description=f"Regiões aceitas: {j.get('location') or 'n/d'}\n{description}",
                city=j.get("location") or None,
                is_remote=True,
                published_at=datetime.fromisoformat(pub) if pub else None,
                tags=job_tags,
            ))
        return out
