"""Confere se o app pediu uma busca que ainda não foi disparada.

Roda no workflow "Analisar currículos" (a cada 15 minutos). Imprime `dispatch=true` quando
o workflow deve disparar o worker, e marca os pedidos como disparados.

Uso:  python -m recrutador.pending_search >> "$GITHUB_OUTPUT"
"""

from __future__ import annotations

import logging
import os
import sys

from dotenv import load_dotenv

from .db import Database

log = logging.getLogger("recrutador.pending_search")


def run() -> None:
    load_dotenv()
    logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    db = Database(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    try:
        ids = db.search_requests_to_dispatch()
    except Exception as exc:  # tabela ainda não criada (migração não aplicada)
        log.warning("pedidos de busca indisponíveis: %s", exc)
        ids = []
    if ids:
        db.mark_dispatched(ids)
        log.info("pending_search: %d pedido(s) de busca do app; disparando o worker", len(ids))
    print(f"dispatch={'true' if ids else 'false'}")


if __name__ == "__main__":
    run()
