"""LinkedIn, Indeed e Glassdoor via um actor da Apify (formato JobSpy).

USO PESSOAL. Esses actors raspam páginas públicas; os termos de uso de LinkedIn, Indeed e
Glassdoor proíbem isso. Não ligar esta fonte numa versão comercial do app.

Só entra na rodada quando existe o secret APIFY_TOKEN. Configuração por variáveis:
  APIFY_ACTOR        actor no formato dono/nome (padrão abaixo); qualquer actor com saída JobSpy serve
  APIFY_MAX_RESULTS  total de vagas por rodada (padrão 20) — controla o custo, cobrado por resultado.
                     1/4 são vagas no Brasil e 3/4 remotas em outros países (20 → 5 + 15)
  APIFY_BR_RESULTS   opcional: quantas das vagas do total são do Brasil (substitui a divisão 1/4)
  APIFY_SITES        sites separados por vírgula (padrão linkedin,indeed,glassdoor)
"""

from __future__ import annotations

import hashlib
import math
import logging
import time
from datetime import datetime, timezone

import httpx

from ..geo import infer_country
from ..models import RawJob
from .base import JobSource, strip_html

log = logging.getLogger(__name__)

API = "https://api.apify.com/v2"
DEFAULT_ACTOR = "iskoren/multi-job-board-scraper"
INTERVAL = {"yearly": "year", "monthly": "month", "hourly": "hour", "weekly": None, "daily": None}

# Duas buscas por termo: vagas no Brasil e vagas remotas em outros países
SCOPES = [
    {"key": "br", "code": "BR", "location": "Brazil", "countryIndeed": "brazil", "isRemote": False},
    {"key": "remote", "code": None, "location": "", "countryIndeed": "usa", "isRemote": True},
]


class ApifyJobsSource(JobSource):
    name = "apify"

    def __init__(self, client: httpx.Client, token: str, actor: str = DEFAULT_ACTOR, br_results: int = 5,
                 remote_results: int = 15, sites: list[str] | None = None, max_terms: int = 2, hours_old: int = 48,
                 max_wait_seconds: int = 600):
        super().__init__(client)
        self.headers = {"Authorization": f"Bearer {token}"}
        self.actor = actor.replace("/", "~")  # a API usa dono~nome
        self.budget = {"br": br_results, "remote": remote_results}  # vagas por rodada em cada escopo
        self.sites = sites or ["linkedin", "indeed", "glassdoor"]
        self.max_terms = max_terms
        self.hours_old = hours_old
        self.max_wait = max_wait_seconds

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        terms = search_terms[: self.max_terms]
        jobs: list[RawJob] = []
        for scope in SCOPES:
            budget = self.budget[scope["key"]]
            if budget <= 0 or not terms:
                continue
            # O actor limita por site e por busca; pede o mínimo que cobre o total e corta no fim
            per_site = max(1, math.ceil(budget / (len(terms) * len(self.sites))))
            found: list[RawJob] = []
            for term in terms:
                payload = {
                    "searchTerm": term,
                    "location": scope["location"],
                    "countryIndeed": scope["countryIndeed"],
                    "isRemote": scope["isRemote"],
                    "sites": self.sites,
                    "maxResults": per_site,
                    "hoursOld": self.hours_old,
                    "descriptionFormat": "markdown",
                    "linkedinFetchDescription": True,
                }
                found.extend(self.parse(self._run(payload), scope["code"]))
            jobs.extend(self.pick(found, scope["key"], budget))
        return jobs

    @staticmethod
    def pick(found: list[RawJob], scope: str, budget: int) -> list[RawJob]:
        """Mantém só as do escopo (Brasil / outros países), sem repetir, as mais recentes primeiro."""
        seen: set[str] = set()
        out = []
        oldest = datetime.min.replace(tzinfo=timezone.utc)
        for j in sorted(found, key=lambda j: j.published_at or oldest, reverse=True):
            in_scope = j.country == "BR" if scope == "br" else j.country != "BR"
            if in_scope and j.url not in seen:
                seen.add(j.url)
                out.append(j)
        return out[:budget]

    def _run(self, payload: dict) -> list[dict]:
        """Inicia o actor, espera terminar (até max_wait) e lê o dataset."""
        resp = self.client.post(f"{API}/acts/{self.actor}/runs", params={"waitForFinish": 60},
                                headers=self.headers, json=payload, timeout=90)
        resp.raise_for_status()
        run = resp.json()["data"]
        deadline = time.monotonic() + self.max_wait
        while run["status"] in ("READY", "RUNNING") and time.monotonic() < deadline:
            r = self.client.get(f"{API}/actor-runs/{run['id']}", params={"waitForFinish": 60},
                                headers=self.headers, timeout=90)
            r.raise_for_status()
            run = r.json()["data"]
        if run["status"] != "SUCCEEDED":
            log.warning("apify: execução %s terminou com status %s", run["id"], run["status"])
            if run["status"] in ("READY", "RUNNING"):
                return []
        items = self.client.get(f"{API}/datasets/{run['defaultDatasetId']}/items",
                                params={"clean": "true", "format": "json"}, headers=self.headers, timeout=90)
        items.raise_for_status()
        return items.json()

    @staticmethod
    def parse(items: list[dict], scope_country: str | None) -> list[RawJob]:
        out = []
        for j in items:
            url = j.get("job_url") or j.get("job_url_direct") or ""
            title = (j.get("title") or "").strip()
            if not url or not title:
                continue
            location = j.get("location") or ""
            if isinstance(location, dict):  # alguns actors devolvem {city, state, country}
                location = ", ".join(str(v) for v in (location.get("city"), location.get("state"),
                                                      location.get("country")) if v)
            remote = bool(j.get("is_remote"))
            country = infer_country(location)
            if country is None and scope_country:  # achada na busca do Brasil, sem local informado
                country = scope_country
            posted = j.get("date_posted")
            published = None
            if posted:
                try:
                    published = datetime.fromisoformat(str(posted)[:10]).replace(tzinfo=timezone.utc)
                except ValueError:
                    published = None
            interval = INTERVAL.get(str(j.get("salary_interval") or "").lower())
            has_salary = j.get("salary_min") is not None and interval is not None
            out.append(RawJob(
                source=str(j.get("site") or "apify").lower(),  # linkedin / indeed / glassdoor
                external_id=str(j.get("id") or hashlib.sha1(url.encode()).hexdigest()),
                url=url,
                title=title,
                company=(j.get("company") or "").strip(),
                description=strip_html(j.get("description")) if "<" in str(j.get("description") or "")
                else (j.get("description") or ""),
                country=country,
                city=location or None,
                is_remote=remote,
                salary_min=j.get("salary_min") if has_salary else None,
                salary_max=j.get("salary_max") if has_salary else None,
                salary_period=interval if has_salary else None,
                currency=j.get("salary_currency") if has_salary else None,
                published_at=published,
            ))
        return out
