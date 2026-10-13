"""Transforma feedback do usuário em preferências aprendidas (tabela learned_prefs).

Não há treino de modelo: são pesos simples, visíveis e editáveis pelo usuário no app.
"""

from __future__ import annotations

from .dedup import normalize_company
from .salary import MAX_REMOTE_DISCOUNT, MIN_REMOTE_DISCOUNT

# Pontos somados/subtraídos na nota por evento
EVENT_WEIGHTS = {"saved": 3.0, "applied": 5.0, "interview": 6.0, "offer": 8.0, "dismissed": -4.0, "rejected": -1.0}
MAX_ABS_WEIGHT = 20.0
LEARNING_RATE = 0.3


def apply_event(prefs: dict[str, float], kind: str, *, company: str | None = None,
                country: str | None = None, reason: str | None = None) -> dict[str, float]:
    """Atualiza pesos de empresa/país a partir de um evento. Retorna um novo dicionário."""
    out = dict(prefs)
    delta = EVENT_WEIGHTS.get(kind, 0.0)
    if not delta:
        return out

    targets = []
    if kind == "dismissed" and reason:
        # O motivo do descarte diz o que penalizar; outros motivos (salário, stack) não mexem em empresa/país
        if reason == "country" and country:
            targets.append(f"country:{country.upper()}")
        if reason == "company" and company:
            targets.append(f"company:{normalize_company(company)}")
    else:
        if company:
            targets.append(f"company:{normalize_company(company)}")
        if country:
            targets.append(f"country:{country.upper()}")

    for key in targets:
        out[key] = max(-MAX_ABS_WEIGHT, min(MAX_ABS_WEIGHT, out.get(key, 0.0) + delta))
    return out


def update_remote_discount(current: float, suggested_target: float, user_value: float,
                           market_p25: float) -> float:
    """Quando o usuário edita a pretensão remota, aproxima o desconto d da escolha dele.

    O desconto implícito na escolha é user_value / market_p25. Movemos d nessa direção
    com taxa LEARNING_RATE, dentro dos limites aceitos.
    """
    if market_p25 <= 0 or user_value <= 0 or suggested_target <= 0:
        return current
    implied = user_value / market_p25
    new = current + LEARNING_RATE * (implied - current)
    return round(min(max(new, MIN_REMOTE_DISCOUNT), MAX_REMOTE_DISCOUNT), 3)
