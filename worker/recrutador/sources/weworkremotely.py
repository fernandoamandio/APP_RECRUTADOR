from __future__ import annotations

import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

import httpx

from ..models import RawJob
from .base import JobSource, specific_words, strip_html

FEEDS = [
    "https://weworkremotely.com/categories/remote-back-end-programming-jobs.rss",
    "https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss",
    "https://weworkremotely.com/categories/remote-devops-sysadmin-jobs.rss",
]


class WeWorkRemotelySource(JobSource):
    name = "weworkremotely"

    def __init__(self, client: httpx.Client, feeds: list[str] | None = None):
        super().__init__(client)
        self.feeds = feeds or FEEDS

    def fetch(self, search_terms: list[str], tags: list[str]) -> list[RawJob]:
        jobs: list[RawJob] = []
        for feed in self.feeds:
            resp = self.client.get(feed)
            resp.raise_for_status()
            jobs.extend(self.parse(resp.text, search_terms + tags))
        return jobs

    @staticmethod
    def parse(xml_text: str, keywords: list[str]) -> list[RawJob]:
        words = specific_words(keywords)
        out = []
        for item in ET.fromstring(xml_text).iter("item"):
            raw_title = (item.findtext("title") or "").strip()
            company, _, position = raw_title.partition(":")
            if not position:
                company, position = "", raw_title
            description = strip_html(item.findtext("description"))
            text = f"{position} {description}".lower()
            if words and not any(w in text for w in words):
                continue
            link = (item.findtext("link") or "").strip()
            pub = item.findtext("pubDate")
            out.append(RawJob(
                source="weworkremotely",
                external_id=(item.findtext("guid") or link).strip(),
                url=link,
                title=position.strip(),
                company=company.strip(),
                description=description,
                city=(item.findtext("region") or "").strip() or None,
                is_remote=True,
                published_at=parsedate_to_datetime(pub) if pub else None,
            ))
        return out
