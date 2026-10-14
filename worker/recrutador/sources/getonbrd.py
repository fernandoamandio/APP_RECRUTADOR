from __future__ import annotations

import time
from datetime import datetime, timezone

import httpx

from ..models import RawJob
from .base import JobSource, strip_html

BASE_URL = "https://www.getonbrd.com/api/v0"

# Nomes de país em espanhol/inglês que aparecem em `countries` -> ISO 3166-1
COUNTRY_CODES = {
    "chile": "CL", "argentina": "AR", "brasil": "BR", "brazil": "BR", "colombia": "CO", "méxico": "MX",
    "mexico": "MX", "perú": "PE", "peru": "PE", "uruguay": "UY", "ecuador": "EC", "bolivia": "BO",
    "paraguay": "PY", "venezuela": "VE", "costa rica": "CR", "españa": "ES", "spain": "ES",
    "estados unidos": "US", "united states": "US",
}


class GetOnBoardSource(JobSource):
    """API pública da Get on Board (tech na América Latina). A leitura de vagas não exige chave.

    A busca não traz o nome da empresa, só o id; buscamos o nome em /companies/{id}
    uma vez por empresa e guardamos em cache durante a rodada.
    """

    name = "getonbrd"

    def __init__(self, client: httpx.Client, per_page: int = 50, max_terms: int = 3, pause: float = 1.5):
        super().__init__(client)
        self.per_page = per_page
        self.max_terms = max_terms  # poucas buscas por rodada: a API recusa (403) rajadas de chamadas
        self.pause = pause  # segundos entre chamadas
        self._company_names: dict[str, str] = {}

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for term in search_terms[: self.max_terms]:
            time.sleep(self.pause)
            resp = self.client.get(f"{BASE_URL}/search/jobs", params={"query": term, "per_page": self.per_page})
            resp.raise_for_status()
            jobs.extend(self.parse(resp.json(), self.company_name))
        return jobs

    def company_name(self, company_id: str) -> str:
        if company_id not in self._company_names:
            try:
                time.sleep(self.pause)
                resp = self.client.get(f"{BASE_URL}/companies/{company_id}")
                resp.raise_for_status()
                self._company_names[company_id] = resp.json()["data"]["attributes"].get("name", "")
            except (httpx.HTTPError, KeyError, ValueError):
                self._company_names[company_id] = ""
        return self._company_names[company_id]

    @staticmethod
    def parse(payload: dict, company_name) -> list[RawJob]:
        out = []
        for item in payload.get("data", []):
            a = item.get("attributes", {})
            company_id = str(((a.get("company") or {}).get("data") or {}).get("id", ""))
            name = company_name(company_id) if company_id else ""
            countries = a.get("countries") or []
            country = COUNTRY_CODES.get(countries[0].lower()) if len(countries) == 1 else None
            remote = bool(a.get("remote")) or a.get("remote_modality") == "fully_remote"
            sections = [a.get("description"), a.get("functions"), a.get("desirable"), a.get("benefits")]
            zone = a.get("remote_zone")
            location_note = f"Modalidade: {a.get('remote_modality') or 'n/d'}; zona remota: {zone or 'n/d'}; países: {', '.join(countries) or 'n/d'}"
            published = a.get("published_at")
            out.append(RawJob(
                source="getonbrd",
                external_id=item["id"],
                url=(item.get("links") or {}).get("public_url", ""),
                title=(a.get("title") or "").strip(),
                company=name.strip(),
                description=f"{location_note}\n" + "\n".join(strip_html(s) for s in sections if s),
                country=None if remote else country,
                city=", ".join(countries) or None,
                is_remote=remote,
                # Get on Board publica faixas em dólares por mês
                salary_min=a.get("min_salary"),
                salary_max=a.get("max_salary"),
                salary_period="month" if a.get("min_salary") else None,
                currency="USD" if a.get("min_salary") else None,
                published_at=datetime.fromtimestamp(published, tz=timezone.utc) if published else None,
            ))
        return out
