"""Processa currículos e cover letters enviados pelo app.

Roda a cada 15 minutos (.github/workflows/documents.yml) e no início de cada rodada do worker:
1. Currículo novo (PDF próprio ou exportado do LinkedIn) → o Claude extrai o perfil profissional.
2. Qualquer documento novo → o match de todas as vagas é refeito com os documentos novos,
   já calculando as primeiras vagas para o resultado aparecer logo no app.

Uso:  python -m recrutador.documents
"""

from __future__ import annotations

import logging
import os

import anthropic
from dotenv import load_dotenv

from .db import Database
from .profile_extract import extract_profile, to_career_profile_row

log = logging.getLogger("recrutador.documents")


def process_documents(db: Database, claude: anthropic.Anthropic, profile_model: str, match_model: str) -> int:
    from .main import run_matching  # import tardio: main também importa este módulo

    pending = db.pending_documents()
    users = sorted({d["user_id"] for d in pending})
    for uid in users:
        if not db.has_ai_consent(uid):
            log.info("usuário %s: documentos aguardando consentimento para análise por IA", uid[:8])
            continue
        docs = {d["kind"]: d for d in pending if d["user_id"] == uid}
        try:
            if "cv" in docs:
                cv = db.download(docs["cv"]["storage_path"])
                cover_doc = docs.get("cover_letter")
                cover = db.download(cover_doc["storage_path"]) if cover_doc else db.latest_documents(uid).get("cover_letter")
                profile = extract_profile(claude, profile_model, cv, cover)
                db.save_extracted_profile(to_career_profile_row(uid, docs["cv"]["id"], profile))
                log.info("usuário %s: perfil extraído do currículo (%d cargos-alvo)", uid[:8],
                         len(profile.get("target_titles") or []))
            for kind in docs:
                db.mark_analyzed(uid, kind)
        except (anthropic.APIError, ValueError, KeyError) as exc:
            log.warning("usuário %s: falha ao analisar documentos: %s", uid[:8], exc)
            continue

        # Documentos novos mudam a comparação: refaz o match e já calcula as primeiras vagas
        db.reset_matches(uid)
        row = db.career_profile(uid) or {}
        done = run_matching(db, claude, match_model, uid, row)
        log.info("usuário %s: match refeito com os documentos novos em %d vagas", uid[:8], done)
    return len(users)


def run() -> None:
    load_dotenv()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    db = Database(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    n = process_documents(db, anthropic.Anthropic(),
                          os.getenv("CLAUDE_PROFILE_MODEL", "claude-sonnet-5-5"),
                          os.getenv("CLAUDE_MATCH_MODEL", "claude-haiku-5-5"))
    log.info("documentos: %d usuário(s) processado(s)", n)


if __name__ == "__main__":
    run()
