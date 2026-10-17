"""Autoteste da análise de currículo e do match, sem gravar nada no banco.

Gera um PDF fictício de currículo, pede à IA o perfil e um match com uma vaga de exemplo.
Usa o provedor, o modelo e a chave do primeiro usuário que cadastrou a IA no app.
Uso:  python -m recrutador.selftest
"""

from __future__ import annotations

import logging
import os

from dotenv import load_dotenv

from .db import Database
from .matching import CandidateMaterial, match
from .models import RawJob
from .profile_extract import extract_profile

log = logging.getLogger("recrutador.selftest")

CV_LINES = [
    "Joao Exemplo - Desenvolvedor PL/SQL Senior (curriculo ficticio para teste)",
    "Campinas, SP, Brasil - Ingles avancado",
    "Experiencia: 10 anos com Oracle Database 12c/19c, PL/SQL, tuning de SQL, packages e triggers.",
    "Empresa X (2019-2026): procedures PL/SQL para faturamento hospitalar; reduzi o batch noturno em 40%.",
    "Empresa Y (2015-2019): integracoes Oracle Fusion e relatorios BI Publisher.",
    "Formacao: Bacharel em Ciencia da Computacao.",
]


def tiny_pdf(lines: list[str]) -> bytes:
    """Monta um PDF mínimo válido com texto (sem dependências)."""
    text = "BT /F1 11 Tf 50 780 Td 14 TL " + " ".join(
        f"({ln.replace('(', '[').replace(')', ']')}) Tj T*" for ln in lines) + " ET"
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R "
        b"/Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(text) + text.encode("latin-1") + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def run() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    load_dotenv()
    db = Database(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    ai = next((a for a in map(db.ai_client, db.users_with_ai()) if a), None)
    assert ai, "nenhum usuário cadastrou provedor e chave de IA no app"
    log.info("selftest IA: %s", ai.label)
    pdf = tiny_pdf(CV_LINES)

    profile = extract_profile(ai, pdf)
    log.info("selftest perfil: cargos=%s | senioridade=%s | stack=%s | busca=%s",
             profile.get("target_titles"), profile.get("seniority"),
             [s.get("name") for s in profile.get("stack", [])], profile.get("search_terms"))
    assert profile.get("target_titles"), "perfil sem cargos-alvo"

    job = RawJob(source="selftest", external_id="1", url="", title="Senior Oracle PL/SQL Developer",
                 company="Empresa Exemplo", country="BR", city="Campinas, SP",
                 description="Requisitos: PL/SQL avançado, Oracle 19c, tuning de SQL. Desejável: Python e AWS.")
    result = match(ai, CandidateMaterial(cv_pdf=pdf), job)
    log.info("selftest match: %d%% | atende=%s | falta=%s", result.percent, result.strengths, result.gaps)
    assert 0 <= result.percent <= 100
    log.info("selftest OK")


if __name__ == "__main__":
    run()
