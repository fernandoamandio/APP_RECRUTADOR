"""Acesso ao Supabase com a service role (só no worker)."""

from __future__ import annotations

from datetime import datetime, timezone

from supabase import Client, create_client

from .llm import AIClient
from .models import CareerProfile, Household, RawJob, TriageResult


class Database:
    def __init__(self, url: str, service_key: str):
        self.sb: Client = create_client(url, service_key)

    # ---------- usuários ----------

    def confirmed_profiles(self) -> list[dict]:
        """Usuários com perfil profissional revisado e consentimento de IA."""
        # career_profile e profiles apontam ambas para auth.users (não uma para a outra),
        # então o PostgREST não consegue juntá-las numa consulta só: buscamos em duas.
        rows = self.sb.table("career_profile").select("*").not_.is_("confirmed_at", "null").execute().data
        if not rows:
            return []
        consented = {
            p["user_id"] for p in self.sb.table("profiles").select("user_id")
            .in_("user_id", [r["user_id"] for r in rows]).not_.is_("consent_ai_at", "null").execute().data
        }
        return [r for r in rows if r["user_id"] in consented]

    @staticmethod
    def to_career_profile(row: dict) -> CareerProfile:
        kw = row.get("keywords") or {}
        return CareerProfile(target_titles=row["target_titles"], stack=row["stack"], seniority=row.get("seniority"),
                             search_terms=kw.get("search_terms", []), remoteok_tags=kw.get("remoteok_tags", []))

    def household(self, user_id: str) -> Household:
        rows = self.sb.table("household").select("*").eq("user_id", user_id).execute().data
        if not rows:
            return Household()  # padrão: pessoa sozinha
        r = rows[0]
        return Household(married=r.get("marital_status") == "married", children_ages=r.get("children_ages") or [])

    def salary_prefs(self, user_id: str) -> dict[tuple[str, str], dict]:
        rows = self.sb.table("salary_prefs").select("*").eq("user_id", user_id).execute().data
        return {(r["country"], r["modality"]): r for r in rows}

    def learned_prefs(self, user_id: str) -> dict[str, float]:
        rows = self.sb.table("learned_prefs").select("key, value").eq("user_id", user_id).execute().data
        return {r["key"]: float(r["value"]) for r in rows if isinstance(r["value"], (int, float))}

    def latest_documents(self, user_id: str) -> dict[str, bytes]:
        """Baixa a versão mais recente do currículo e da cover letter do usuário ({kind: bytes})."""
        rows = (self.sb.table("documents").select("kind, storage_path, created_at").eq("user_id", user_id)
                .order("created_at", desc=True).execute().data)
        out: dict[str, bytes] = {}
        for r in rows:
            if r["kind"] in out:
                continue
            try:
                out[r["kind"]] = self.sb.storage.from_("documents").download(r["storage_path"])
            except Exception:  # documento apagado do Storage: segue sem ele
                continue
        return out

    def pending_documents(self) -> list[dict]:
        """Documentos ainda não analisados (o mais recente de cada tipo, por usuário)."""
        rows = (self.sb.table("documents").select("id, user_id, kind, storage_path, created_at")
                .is_("analyzed_at", "null").order("created_at", desc=True).execute().data)
        seen: set[tuple[str, str]] = set()
        out = []
        for r in rows:
            if (r["user_id"], r["kind"]) not in seen:
                seen.add((r["user_id"], r["kind"]))
                out.append(r)
        return out

    def download(self, storage_path: str) -> bytes:
        return self.sb.storage.from_("documents").download(storage_path)

    def mark_analyzed(self, user_id: str, kind: str) -> None:
        """Marca todas as versões pendentes daquele tipo (as antigas ficam superadas pela mais recente)."""
        self.sb.table("documents").update({"analyzed_at": datetime.now(timezone.utc).isoformat()}) \
            .eq("user_id", user_id).eq("kind", kind).is_("analyzed_at", "null").execute()

    def save_extracted_profile(self, row: dict) -> None:
        # O usuário enviou o currículo de propósito: o perfil já vale para a busca (editável no app)
        row = {**row, "confirmed_at": datetime.now(timezone.utc).isoformat(),
               "updated_at": datetime.now(timezone.utc).isoformat()}
        self.sb.table("career_profile").upsert(row, on_conflict="user_id").execute()

    def career_profile(self, user_id: str) -> dict | None:
        rows = self.sb.table("career_profile").select("*").eq("user_id", user_id).execute().data
        return rows[0] if rows else None

    def has_ai_consent(self, user_id: str) -> bool:
        rows = self.sb.table("profiles").select("consent_ai_at").eq("user_id", user_id).execute().data
        return bool(rows and rows[0].get("consent_ai_at"))

    def pending_matches(self, user_id: str, limit: int) -> list[str]:
        """Vagas do feed ainda sem match calculado, as de maior nota primeiro."""
        rows = (self.sb.table("job_matches").select("job_id").eq("user_id", user_id).is_("matched_at", "null")
                .in_("status", ["new", "seen", "saved"]).order("score", desc=True).limit(limit).execute().data)
        return [r["job_id"] for r in rows]

    def job_for_match(self, job_id: str) -> RawJob | None:
        rows = self.sb.table("jobs").select("title, company, country, city, description").eq("id", job_id).execute().data
        if not rows:
            return None
        r = rows[0]
        return RawJob(source="db", external_id=job_id, url="", title=r["title"], company=r["company"],
                      country=r.get("country"), city=r.get("city"), description=r.get("description") or "")

    def save_match_result(self, user_id: str, job_id: str, pct: int, strengths: list[str], gaps: list[str]) -> None:
        self.sb.table("job_matches").update({
            "match_pct": pct, "match_strengths": strengths, "match_gaps": gaps,
            "matched_at": datetime.now(timezone.utc).isoformat(),
        }).eq("user_id", user_id).eq("job_id", job_id).execute()

    def reset_matches(self, user_id: str) -> None:
        """Novo currículo ou cover letter: o match de todas as vagas precisa ser refeito."""
        self.sb.table("job_matches").update({"matched_at": None}).eq("user_id", user_id).execute()

    def feedback_with_jobs(self, user_id: str) -> list[dict]:
        return (self.sb.table("feedback_events").select("kind, reason, value, jobs(company, country)")
                .eq("user_id", user_id).order("created_at").execute().data)

    def save_learned(self, user_id: str, prefs: dict[str, float]) -> None:
        if prefs:
            self.sb.table("learned_prefs").upsert(
                [{"user_id": user_id, "key": k, "value": v} for k, v in prefs.items()],
                on_conflict="user_id,key",
            ).execute()

    # ---------- vagas ----------

    def known_hashes(self, hashes: list[str]) -> dict[str, str]:
        """dedup_hash -> job_id das vagas já existentes."""
        out: dict[str, str] = {}
        for i in range(0, len(hashes), 200):
            rows = self.sb.table("jobs").select("id, dedup_hash").in_("dedup_hash", hashes[i:i + 200]).execute().data
            out.update({r["dedup_hash"]: r["id"] for r in rows})
        return out

    def upsert_job(self, h: str, job: RawJob, sources: list[RawJob]) -> str:
        row = {
            "dedup_hash": h, "title": job.title, "company": job.company, "country": job.country,
            "city": job.city, "is_remote": job.is_remote, "salary_min": job.salary_min,
            "salary_max": job.salary_max, "salary_period": job.salary_period, "currency": job.currency,
            "description": job.description, "last_seen_at": datetime.now(timezone.utc).isoformat(),
            "published_at": job.published_at.isoformat() if job.published_at else None,
        }
        job_id = self.sb.table("jobs").upsert(row, on_conflict="dedup_hash").execute().data[0]["id"]
        self.sb.table("job_sources").upsert(
            [{"job_id": job_id, "source": s.source, "external_id": s.external_id, "url": s.url} for s in sources],
            on_conflict="source,external_id",
        ).execute()
        return job_id

    def jobs_without_country(self) -> list[dict]:
        return self.sb.table("jobs").select("id, city").is_("country", "null").not_.is_("city", "null").execute().data

    def set_job_country(self, job_id: str, country: str) -> None:
        self.sb.table("jobs").update({"country": country}).eq("id", job_id).execute()
        if country == "BR":  # vaga no Brasil: elegível para quem mora aqui, sem depender de visto ou remoto
            self.sb.table("job_eligibility").update({
                "category": "local_br", "evidence": "Vaga localizada no Brasil", "confidence": 1.0,
            }).eq("job_id", job_id).execute()

    def eligibility(self, job_ids: list[str]) -> dict[str, dict]:
        out: dict[str, dict] = {}
        for i in range(0, len(job_ids), 200):
            rows = self.sb.table("job_eligibility").select("*").in_("job_id", job_ids[i:i + 200]).execute().data
            out.update({r["job_id"]: r for r in rows})
        return out

    def save_eligibility(self, job_id: str, t: TriageResult) -> None:
        self.sb.table("job_eligibility").upsert({
            "job_id": job_id, "category": t.category.value, "evidence": t.evidence,
            "confidence": round(t.confidence, 2), "sponsor_registered": t.sponsor_registered, "model": t.model,
        }).execute()

    def save_match(self, user_id: str, job_id: str, score: int, reasons: list[str], salary: dict | None) -> None:
        # ignore_duplicates: não sobrescreve o status que o usuário já deu à vaga
        self.sb.table("job_matches").upsert({
            "user_id": user_id, "job_id": job_id, "score": score, "reasons": reasons, "salary_suggested": salary,
        }, on_conflict="user_id,job_id", ignore_duplicates=True).execute()

    # ---------- referências ----------

    def cost_items(self, country: str, city: str | None) -> dict[str, float]:
        rows = (self.sb.table("cost_of_living").select("city, item, monthly")
                .eq("country", country).in_("city", [city or "", ""]).execute().data)
        # o valor da cidade tem prioridade sobre a média do país
        items: dict[str, float] = {}
        for r in sorted(rows, key=lambda r: r["city"] != ""):
            items[r["item"]] = float(r["monthly"])
        return items

    def tax_rate(self, country: str, annual: float) -> float | None:
        rows = (self.sb.table("tax_rates").select("annual_from, effective_rate").eq("country", country)
                .lte("annual_from", annual).order("annual_from", desc=True).limit(1).execute().data)
        return float(rows[0]["effective_rate"]) if rows else None

    def sponsor_registry(self) -> dict[str, set[str]]:
        rows = self.sb.table("sponsor_registry").select("country, company_normalized").execute().data
        out: dict[str, set[str]] = {}
        for r in rows:
            out.setdefault(r["country"], set()).add(r["company_normalized"])
        return out

    # ---------- buscas pedidas pelo app ----------

    def claim_search_requests(self) -> list[dict]:
        """Marca como em andamento os pedidos do botão "Buscar vagas". Devolve [{id, user_id}]."""
        now = datetime.now(timezone.utc).isoformat()
        rows = (self.sb.table("search_requests").update({"status": "running", "started_at": now})
                .eq("status", "pending").execute().data)
        return [{"id": r["id"], "user_id": r["user_id"]} for r in rows]

    def users_with_ai(self) -> list[str]:
        return [r["user_id"] for r in self.sb.table("user_ai_settings").select("user_id").execute().data]

    def ai_client(self, user_id: str) -> AIClient | None:
        """Provedor, modelo e chave de IA que o usuário cadastrou no app (chave guardada no Vault)."""
        try:
            rows = self.sb.rpc("ai_credentials", {"p_user": user_id}).execute().data or []
        except Exception as exc:  # migração ainda não aplicada
            import logging
            logging.getLogger(__name__).warning("credenciais de IA indisponíveis: %s", exc)
            return None
        row = rows[0] if isinstance(rows, list) and rows else (rows if isinstance(rows, dict) else None)
        if not row or not row.get("api_key"):
            return None
        return AIClient(provider=row["provider"], model=row["model"], api_key=row["api_key"],
                        contact_email=row.get("contact_email") or "")

    def finish_search_requests(self, ids: list[int], ok: bool) -> None:
        if ids:
            self.sb.table("search_requests").update({
                "status": "done" if ok else "failed", "finished_at": datetime.now(timezone.utc).isoformat(),
            }).in_("id", ids).execute()

    def search_requests_to_dispatch(self, wait_minutes: int = 5, redispatch_minutes: int = 30) -> list[int]:
        """Pedidos que o banco não conseguiu disparar na hora (sem token no Vault ou falha)."""
        now = datetime.now(timezone.utc)
        rows = (self.sb.table("search_requests").select("id, requested_at, dispatched_at")
                .eq("status", "pending").execute().data)
        out = []
        for r in rows:
            requested = datetime.fromisoformat(r["requested_at"])
            dispatched = datetime.fromisoformat(r["dispatched_at"]) if r.get("dispatched_at") else None
            if (now - requested).total_seconds() < wait_minutes * 60:
                continue  # o disparo imediato pode estar a caminho
            if dispatched and (now - dispatched).total_seconds() < redispatch_minutes * 60:
                continue
            out.append(r["id"])
        return out

    def mark_dispatched(self, ids: list[int]) -> None:
        if ids:
            self.sb.table("search_requests").update({"dispatched_at": datetime.now(timezone.utc).isoformat()}) \
                .in_("id", ids).execute()
