"""Uma rodada do worker: coleta → deduplicação → pré-filtro → triagem → pontuação → salário → match.

Uso:  python -m recrutador.main
Agendado pelo GitHub Actions (.github/workflows/worker.yml) a cada 6 horas.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache

import anthropic
import httpx
from dotenv import load_dotenv

from .db import Database
from .dedup import deduplicate, merge
from .learning import apply_event
from .matching import CandidateMaterial, match, profile_as_text
from .models import Eligibility, RawJob
from .prefilter import prefilter
from .salary import market_from_histogram, suggest_relocation, suggest_remote, family_monthly_cost
from .scoring import score
from .sources import (
    AdzunaSource, ArbeitnowSource, GetOnBoardSource, InfoJobsSource, JobSource, JoobleSource,
    RemoteOKSource, WeWorkRemotelySource, WorkingNomadsSource,
)
from .sponsors import SponsorRegistry
from .triage import triage

log = logging.getLogger("recrutador")

MIN_SCORE = 50              # abaixo disso a vaga não entra no feed
MAX_TRIAGE_PER_RUN = 300    # teto de custo de IA por rodada
MAX_SEARCH_TERMS = 8
MAX_MATCH_PER_USER = 60     # vagas com match calculado por usuário a cada rodada


def build_sources(client: httpx.Client) -> tuple[list[JobSource], AdzunaSource | None]:
    # Fontes sem chave: sempre ativas
    sources: list[JobSource] = [
        RemoteOKSource(client), WeWorkRemotelySource(client), WorkingNomadsSource(client),
        ArbeitnowSource(client), GetOnBoardSource(client),
    ]
    # Fontes com chave: só entram quando os secrets existem
    if os.getenv("INFOJOBS_CLIENT_ID") and os.getenv("INFOJOBS_CLIENT_SECRET"):
        sources.append(InfoJobsSource(client, os.environ["INFOJOBS_CLIENT_ID"], os.environ["INFOJOBS_CLIENT_SECRET"]))
    adzuna = None
    if os.getenv("ADZUNA_APP_ID") and os.getenv("ADZUNA_APP_KEY"):
        countries = os.getenv("ADZUNA_COUNTRIES", "br,gb,nl,de,us,ca").split(",")
        adzuna = AdzunaSource(client, os.environ["ADZUNA_APP_ID"], os.environ["ADZUNA_APP_KEY"], countries)
        sources.append(adzuna)
    if os.getenv("JOOBLE_API_KEY"):
        sources.append(JoobleSource(client, os.environ["JOOBLE_API_KEY"]))
    return sources, adzuna


def run() -> None:
    load_dotenv()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    db = Database(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    claude = anthropic.Anthropic()
    triage_model = os.getenv("CLAUDE_TRIAGE_MODEL", "claude-haiku-5-5")
    match_model = os.getenv("CLAUDE_MATCH_MODEL", "claude-haiku-5-5")
    contact = os.getenv("CONTACT_EMAIL", "")
    http = httpx.Client(timeout=30, headers={"User-Agent": f"recrutador-worker/0.1 ({contact})"})

    users = db.confirmed_profiles()
    if not users:
        log.info("nenhum usuário com perfil confirmado; nada a fazer")
        return
    profiles = {u["user_id"]: db.to_career_profile(u) for u in users}

    # 1. Coleta: termos de todos os usuários, sem repetir
    terms = list(dict.fromkeys(t for p in profiles.values() for t in p.search_terms))[:MAX_SEARCH_TERMS]
    tags = list(dict.fromkeys(t for p in profiles.values() for t in p.remoteok_tags))
    sources, adzuna = build_sources(http)
    raw: list[RawJob] = [j for s in sources for j in s.safe_fetch(terms, tags)]
    log.info("coletadas %d vagas brutas", len(raw))

    # 2–3. Deduplicação e pré-filtro
    groups = deduplicate(raw)
    jobs: dict[str, tuple[RawJob, list[RawJob]]] = {}
    for h, group in groups.items():
        job = merge(group)
        ok, reason = prefilter(job)
        if ok:
            jobs[h] = (job, group)
        else:
            log.debug("descartada %s @ %s: %s", job.title, job.company, reason)
    log.info("%d vagas únicas após pré-filtro", len(jobs))

    # 4. Persistência e triagem (só vagas ainda não classificadas)
    job_ids = {h: db.upsert_job(h, job, group) for h, (job, group) in jobs.items()}
    known = db.eligibility(list(job_ids.values()))
    sponsors = SponsorRegistry(db.sponsor_registry())
    triaged = 0
    for h, job_id in job_ids.items():
        if job_id in known:
            continue
        if triaged >= MAX_TRIAGE_PER_RUN:
            log.warning("teto de triagem atingido; o restante fica para a próxima rodada")
            break
        try:
            result = triage(claude, triage_model, jobs[h][0], sponsors)
        except anthropic.APIError as exc:
            log.warning("triagem falhou para %s: %s", job_id, exc)
            continue
        db.save_eligibility(job_id, result)
        known[job_id] = {"category": result.category.value}
        triaged += 1
    log.info("%d vagas triadas nesta rodada", triaged)

    @lru_cache(maxsize=256)
    def market(country: str, term: str):
        if not adzuna or country.lower() not in adzuna.countries:
            return None
        try:
            return market_from_histogram(adzuna.histogram(country, term))
        except httpx.HTTPError:
            return None

    # 5. Pontuação e salário por usuário
    for user in users:
        uid = user["user_id"]
        profile = profiles[uid]
        household = db.household(uid)
        prefs = db.salary_prefs(uid)
        learned = relearn(db, uid)
        remote_discount = learned.get("remote_discount", 0.70)
        saved = 0
        for h, job_id in job_ids.items():
            elig = known.get(job_id)
            if not elig:
                continue
            category = Eligibility(elig["category"])
            if category is Eligibility.NOT_ELIGIBLE:
                continue
            job = jobs[h][0]
            s, reasons = score(job, profile, category, learned)
            if s < MIN_SCORE:
                continue
            salary = suggest_salary(db, job, category, household, prefs, remote_discount,
                                    market(job.country, profile.search_terms[0]) if job.country and profile.search_terms else None)
            db.save_match(uid, job_id, s, reasons, salary)
            saved += 1
        log.info("usuário %s: %d vagas no feed", uid[:8], saved)

        # 6. Match do currículo + cover letter com as vagas do feed (as de maior nota primeiro)
        matched = run_matching(db, claude, match_model, uid, user)
        log.info("usuário %s: %d vagas com match calculado", uid[:8], matched)


def run_matching(db: Database, claude: anthropic.Anthropic, model: str, uid: str, profile_row: dict) -> int:
    pending = db.pending_matches(uid, MAX_MATCH_PER_USER)
    log.info("usuário %s: %d vagas aguardando match", uid[:8], len(pending))
    if not pending:
        return 0
    docs = db.latest_documents(uid)
    candidate = CandidateMaterial(cv_pdf=docs.get("cv"), cover_letter_pdf=docs.get("cover_letter"),
                                  profile_text=profile_as_text(profile_row))
    log.info("usuário %s: match usando %s", uid[:8], candidate.source)
    done = 0
    for job_id in pending:
        job = db.job_for_match(job_id)
        if not job:
            log.warning("match: vaga %s não encontrada", job_id)
            continue
        try:
            result = match(claude, model, candidate, job)
        except anthropic.APIError as exc:
            log.warning("match falhou para %s: %s", job_id, exc)
            continue
        db.save_match_result(uid, job_id, result.percent, result.strengths, result.gaps)
        done += 1
    return done


def relearn(db: Database, uid: str) -> dict[str, float]:
    """Recalcula os pesos aprendidos a partir de todo o histórico de feedback do usuário.

    Recalcular do zero é simples e barato no volume do MVP, e mantém o resultado
    reproduzível. O desconto do remoto é preservado (ajustado em outro fluxo).
    """
    current = db.learned_prefs(uid)
    prefs: dict[str, float] = {}
    for ev in db.feedback_with_jobs(uid):
        job = ev.get("jobs") or {}
        prefs = apply_event(prefs, ev["kind"], company=job.get("company"), country=job.get("country"),
                            reason=ev.get("reason"))
    if "remote_discount" in current:
        prefs["remote_discount"] = current["remote_discount"]
    db.save_learned(uid, prefs)
    return prefs


def suggest_salary(db: Database, job: RawJob, category: Eligibility, household, prefs: dict,
                   remote_discount: float, market) -> dict | None:
    """Monta a sugestão conforme a modalidade. Sem dados suficientes, devolve None (o app esconde o valor)."""
    if not job.country or not job.currency:
        return None
    if category is Eligibility.VISA_SPONSOR:
        items = db.cost_items(job.country, job.city)
        needed = {"rent_1br", "rent_3br"}
        if not needed <= items.keys():
            return None
        monthly = family_monthly_cost(items, household)
        tax = db.tax_rate(job.country, monthly * 12 * 1.5) or 0.30
        pref = prefs.get((job.country, "relocation"))
        return suggest_relocation(monthly_cost=monthly, tax_rate=tax, market=market,
                                  user_min=float(pref["min_annual"]) if pref and pref["currency"] == job.currency else None,
                                  currency=job.currency).to_json()
    if category is Eligibility.REMOTE_BR:
        pref = prefs.get((job.country, "remote"))
        # TODO(fase 1): converter o piso brasileiro (BRL) para a moeda da vaga com uma tabela de câmbio
        floor = float(pref["min_annual"]) if pref and pref["currency"] == job.currency else 0.0
        if not market and not floor:
            return None
        return suggest_remote(market_destination=market, brazil_floor=floor, user_min_remote=None,
                              currency=job.currency, discount=remote_discount).to_json()
    return None


if __name__ == "__main__":
    run()
