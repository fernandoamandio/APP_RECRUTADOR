"""Motor de sugestão salarial.

Realocação:  alvo = max( C·12 / ((1−t)(1−s)),  M_P50,  U )
Remoto:      alvo = max( M_P25(destino) · d,  P_Brasil,  U_remoto )

C = custo de vida mensal da família no destino
t = imposto efetivo no destino;  s = taxa de poupança desejada
M = faixa de mercado do cargo no país (P25, P50, P75)
U = pretensão informada (ou aprendida) do usuário
d = desconto do remoto, calibrado pelo aprendizado
Todos os valores anuais brutos, na moeda do destino.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

from .models import Household

DEFAULT_SAVINGS_RATE = 0.20
DEFAULT_REMOTE_DISCOUNT = 0.70
MIN_REMOTE_DISCOUNT, MAX_REMOTE_DISCOUNT = 0.50, 0.90


@dataclass
class MarketRange:
    p25: float
    p50: float
    p75: float


@dataclass
class SalarySuggestion:
    modality: str  # relocation | remote
    min: float
    target: float
    max: float
    currency: str
    period: str = "year"
    warnings: list[str] = field(default_factory=list)
    inputs: dict = field(default_factory=dict)

    def to_json(self) -> dict:
        d = asdict(self)
        for k in ("min", "target", "max"):
            d[k] = round_salary(d[k])
        return d


def round_salary(value: float) -> float:
    """Arredonda para o milhar mais próximo: ninguém pede 81.437."""
    return float(round(value / 1000) * 1000)


def family_monthly_cost(items: dict[str, float], household: Household) -> float:
    """Custo mensal da família a partir dos itens de custo de vida do destino.

    Itens esperados (moeda local, mensal): rent_1br, rent_3br, school_per_child,
    health_per_person, food_per_person, transport_per_person.
    """
    people = household.people
    adults = 2 if household.married else 1
    rent = items["rent_3br"] if household.children_ages else items["rent_1br"]
    return (
        rent
        + items.get("school_per_child", 0) * household.school_age_children
        + items.get("health_per_person", 0) * people
        + items.get("food_per_person", 0) * people
        + items.get("transport_per_person", 0) * adults
    )


def suggest_relocation(*, monthly_cost: float, tax_rate: float, market: MarketRange | None,
                       user_min: float | None, currency: str,
                       savings_rate: float = DEFAULT_SAVINGS_RATE) -> SalarySuggestion:
    if not 0 <= tax_rate < 1 or not 0 <= savings_rate < 1:
        raise ValueError("tax_rate e savings_rate devem estar em [0, 1)")
    cost_floor = monthly_cost * 12 / ((1 - tax_rate) * (1 - savings_rate))
    candidates = [cost_floor, user_min or 0]
    if market:
        candidates.append(market.p50)
    target = max(candidates)

    warnings = []
    if market and market.p75 < cost_floor:
        warnings.append("market_below_family_cost")  # país arriscado para esta composição familiar
    if not market:
        warnings.append("no_market_data")

    low = max(cost_floor, user_min or 0)
    high = max(target, market.p75 if market else target * 1.1)
    return SalarySuggestion(
        modality="relocation", min=min(low, target), target=target, max=high, currency=currency,
        warnings=warnings,
        inputs={"monthly_cost": monthly_cost, "tax_rate": tax_rate, "savings_rate": savings_rate,
                "cost_floor": round(cost_floor, 2), "market": asdict(market) if market else None,
                "user_min": user_min},
    )


def suggest_remote(*, market_destination: MarketRange | None, brazil_floor: float,
                   user_min_remote: float | None, currency: str,
                   discount: float = DEFAULT_REMOTE_DISCOUNT) -> SalarySuggestion:
    """`brazil_floor` já convertido para a moeda do destino e líquido de impostos/custos de PJ."""
    discount = min(max(discount, MIN_REMOTE_DISCOUNT), MAX_REMOTE_DISCOUNT)
    candidates = [brazil_floor, user_min_remote or 0]
    if market_destination:
        candidates.append(market_destination.p25 * discount)
    target = max(candidates)
    low = max(brazil_floor, user_min_remote or 0)
    high = max(target, market_destination.p50 * discount if market_destination else target * 1.1)
    return SalarySuggestion(
        modality="remote", min=min(low, target), target=target, max=high, currency=currency,
        warnings=[] if market_destination else ["no_market_data"],
        inputs={"discount": discount, "brazil_floor": brazil_floor,
                "market": asdict(market_destination) if market_destination else None,
                "user_min_remote": user_min_remote},
    )


def market_from_histogram(histogram: dict[str, int]) -> MarketRange | None:
    """Converte o histograma da Adzuna ({"30000": 12, "35000": 40, ...}) em P25/P50/P75."""
    points = sorted((float(k), n) for k, n in histogram.items() if n > 0)
    total = sum(n for _, n in points)
    if total < 10:  # poucos dados: melhor não sugerir do que sugerir errado
        return None

    def pct(p: float) -> float:
        acc = 0
        for value, n in points:
            acc += n
            if acc >= p * total:
                return value
        return points[-1][0]

    return MarketRange(p25=pct(0.25), p50=pct(0.50), p75=pct(0.75))
