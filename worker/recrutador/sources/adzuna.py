from __future__ import annotations

from datetime import datetime

import httpx

from ..models import RawJob
from .base import JobSource, strip_html

BASE_URL = "https://api.adzuna.com/v1/api/jobs"

# Moeda de cada país da API (os salários vêm na moeda local, anuais)
CURRENCY = {"gb": "GBP", "nl": "EUR", "de": "EUR", "fr": "EUR", "es": "EUR", "it": "EUR", "at": "EUR",
            "be": "EUR", "pl": "PLN", "ch": "CHF", "us": "USD", "ca": "CAD", "au": "AUD", "nz": "NZD",
            "sg": "SGD", "br": "BRL", "mx": "MXN", "in": "INR", "za": "ZAR"}


class AdzunaSource(JobSource):
    name = "adzuna"

    def __init__(self, client: httpx.Client, app_id: str, app_key: str, countries: list[str],
                 results_per_page: int = 50):
        super().__init__(client)
        self.app_id, self.app_key = app_id, app_key
        self.countries = [c.lower() for c in countries]
        self.results_per_page = results_per_page

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for country in self.countries:
            for term in search_terms:
                resp = self.client.get(f"{BASE_URL}/{country}/search/1", params={
                    "app_id": self.app_id, "app_key": self.app_key,
                    "what": term, "results_per_page": self.results_per_page,
                    "max_days_old": 14, "content-type": "application/json",
                })
                resp.raise_for_status()
                jobs.extend(self.parse(resp.json(), country))
        return jobs

    def histogram(self, country: str, what: str) -> dict[str, int]:
        """Distribuição de salários anunciados para o termo no país (base do P25/P50/P75)."""
        resp = self.client.get(f"{BASE_URL}/{country.lower()}/histogram", params={
            "app_id": self.app_id, "app_key": self.app_key, "what": what, "content-type": "application/json",
        })
        resp.raise_for_status()
        return resp.json().get("histogram", {})

    @staticmethod
    def parse(payload: dict, country: str) -> list[RawJob]:
        out = []
        for r in payload.get("results", []):
            created = r.get("created")
            out.append(RawJob(
                source="adzuna",
                external_id=str(r["id"]),
                url=r.get("redirect_url", ""),
                title=r.get("title", "").strip(),
                company=(r.get("company") or {}).get("display_name", "").strip(),
                description=strip_html(r.get("description")),  # a Adzuna trunca a descrição
                country=country.upper(),
                city=(r.get("location") or {}).get("display_name"),
                salary_min=r.get("salary_min"),
                salary_max=r.get("salary_max"),
                salary_period="year" if r.get("salary_min") else None,
                currency=CURRENCY.get(country),
                published_at=datetime.fromisoformat(created.replace("Z", "+00:00")) if created else None,
            ))
        return out
