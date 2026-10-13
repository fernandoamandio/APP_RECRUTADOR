from __future__ import annotations

import hashlib

import httpx

from ..models import RawJob
from .base import JobSource, strip_html


class JoobleSource(JobSource):
    name = "jooble"

    def __init__(self, client: httpx.Client, api_key: str, locations: list[str] | None = None):
        super().__init__(client)
        self.api_key = api_key
        # "" = sem filtro de local; "remote" ajuda a achar vagas remotas; "Brasil" traz as nacionais
        self.locations = locations or ["remote", "", "Brasil"]

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for term in search_terms:
            for location in self.locations:
                resp = self.client.post(f"https://jooble.org/api/{self.api_key}",
                                        json={"keywords": term, "location": location, "page": 1})
                resp.raise_for_status()
                jobs.extend(self.parse(resp.json(), country="BR" if location == "Brasil" else None))
        return jobs

    @staticmethod
    def parse(payload: dict, country: str | None = None) -> list[RawJob]:
        out = []
        for j in payload.get("jobs", []):
            link = j.get("link", "")
            ext_id = str(j.get("id") or hashlib.sha1(link.encode()).hexdigest())
            location = j.get("location") or ""
            out.append(RawJob(
                source="jooble",
                external_id=ext_id,
                url=link,
                title=strip_html(j.get("title")),
                company=(j.get("company") or "").strip(),
                description=strip_html(j.get("snippet")),
                city=location or None,
                country=country,
                is_remote=True if "remote" in location.lower() else None,
            ))
        return out
