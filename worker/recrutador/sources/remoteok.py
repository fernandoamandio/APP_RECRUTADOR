from __future__ import annotations

from datetime import datetime

import httpx

from ..models import RawJob
from .base import JobSource, specific_words, strip_html


class RemoteOKSource(JobSource):
    """API pública do RemoteOK.

    Termos (vêm no primeiro elemento da resposta): link de volta para a vaga no RemoteOK,
    sem nofollow, e citar o RemoteOK como fonte. O app sempre mostra `url` e o nome da fonte.
    A API devolve só as ~100 vagas mais recentes, então filtramos localmente.
    """

    name = "remoteok"

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        resp = self.client.get("https://remoteok.com/api")
        resp.raise_for_status()
        return self.parse(resp.json(), tags, search_terms)

    @staticmethod
    def parse(payload: list, tags: list[str], search_terms: list[str]) -> list[RawJob]:
        wanted_tags = {t.lower() for t in tags}
        wanted_words = specific_words(search_terms)
        out = []
        for j in payload[1:]:  # o elemento 0 é o aviso legal
            job_tags = [t.lower() for t in j.get("tags", [])]
            haystack = f"{j.get('position', '')} {' '.join(job_tags)}".lower()
            if wanted_tags and not (wanted_tags & set(job_tags)) and not any(w in haystack for w in wanted_words):
                continue
            date = j.get("date")
            out.append(RawJob(
                source="remoteok",
                external_id=str(j["id"]),
                url=j.get("url") or f"https://remoteok.com/remote-jobs/{j['id']}",
                title=j.get("position", "").strip(),
                company=j.get("company", "").strip(),
                description=strip_html(j.get("description")),
                city=j.get("location") or None,
                is_remote=True,
                salary_min=j.get("salary_min") or None,
                salary_max=j.get("salary_max") or None,
                salary_period="year" if j.get("salary_min") else None,
                currency="USD" if j.get("salary_min") else None,
                published_at=datetime.fromisoformat(date) if date else None,
                tags=job_tags,
            ))
        return out
