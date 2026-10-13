from __future__ import annotations

from datetime import datetime

import httpx

from ..models import RawJob
from .base import JobSource


class InfoJobsSource(JobSource):
    """API oficial da InfoJobs (Espanha). Exige registrar uma aplicação no portal de
    desenvolvedores e usar client_id/client_secret (autenticação Basic).

    Buscamos só vagas 100% remotas: as presenciais na Espanha costumam exigir
    autorização de trabalho local. A listagem não traz a descrição completa,
    apenas os requisitos mínimos (`requirementMin`).
    """

    name = "infojobs"
    BASE_URL = "https://api.infojobs.net/api/9/offer"

    def __init__(self, client: httpx.Client, client_id: str, client_secret: str, max_results: int = 50):
        super().__init__(client)
        self.auth = httpx.BasicAuth(client_id, client_secret)
        self.max_results = max_results

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for term in search_terms:
            resp = self.client.get(self.BASE_URL, auth=self.auth, params={
                "q": term, "teleworking": "solo-teletrabajo", "maxResults": self.max_results,
            })
            resp.raise_for_status()
            jobs.extend(self.parse(resp.json()))
        return jobs

    @staticmethod
    def parse(payload: dict) -> list[RawJob]:
        out = []
        for o in payload.get("offers", []):
            tele = (o.get("teleworking") or {}).get("value", "")
            province = (o.get("province") or {}).get("value", "")
            published = o.get("published")
            out.append(RawJob(
                source="infojobs",
                external_id=str(o["id"]),
                url=o.get("link", ""),
                title=(o.get("title") or "").strip(),
                company=((o.get("author") or {}).get("name") or "").strip(),
                description=(
                    f"Teletrabalho: {tele or 'n/d'}; local: {', '.join(filter(None, [o.get('city'), province])) or 'n/d'}\n"
                    f"Requisitos mínimos: {o.get('requirementMin') or ''}"
                ),
                country="ES",
                city=o.get("city") or province or None,
                is_remote=True if "solo" in tele.lower() else None,
                published_at=datetime.fromisoformat(published.replace("Z", "+00:00")) if published else None,
            ))
        return out
