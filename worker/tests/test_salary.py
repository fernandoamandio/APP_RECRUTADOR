import pytest

from recrutador.models import Household
from recrutador.salary import (
    MarketRange, family_monthly_cost, market_from_histogram, round_salary, suggest_relocation, suggest_remote,
)

ITEMS = {"rent_1br": 1500, "rent_3br": 2500, "school_per_child": 400, "health_per_person": 150,
         "food_per_person": 350, "transport_per_person": 100}


def test_family_cost_single_person_uses_small_rent():
    assert family_monthly_cost(ITEMS, Household()) == 1500 + 150 + 350 + 100


def test_family_cost_couple_with_two_children_one_in_school_age():
    h = Household(married=True, children_ages=[6, 2])
    # aluguel 3 quartos + 1 escola + 4 pessoas (saúde, comida) + 2 adultos (transporte)
    assert family_monthly_cost(ITEMS, h) == 2500 + 400 + 4 * 150 + 4 * 350 + 2 * 100


def test_relocation_target_covers_cost_of_living_when_market_is_lower():
    s = suggest_relocation(monthly_cost=5000, tax_rate=0.4, savings_rate=0.2,
                           market=MarketRange(60_000, 70_000, 80_000), user_min=None, currency="EUR")
    floor = 5000 * 12 / (0.6 * 0.8)  # 125.000
    assert s.target == pytest.approx(floor)
    assert "market_below_family_cost" in s.warnings


def test_relocation_target_follows_market_when_it_is_higher():
    s = suggest_relocation(monthly_cost=2000, tax_rate=0.3, market=MarketRange(60_000, 75_000, 90_000),
                           user_min=50_000, currency="EUR")
    assert s.target == 75_000
    assert s.max == 90_000
    assert s.min <= s.target <= s.max
    assert s.warnings == []


def test_relocation_respects_user_minimum():
    s = suggest_relocation(monthly_cost=2000, tax_rate=0.3, market=MarketRange(60_000, 75_000, 90_000),
                           user_min=95_000, currency="EUR")
    assert s.target == 95_000


def test_relocation_rejects_invalid_rates():
    with pytest.raises(ValueError):
        suggest_relocation(monthly_cost=1, tax_rate=1.0, market=None, user_min=None, currency="EUR")


def test_remote_is_discounted_market_but_never_below_brazil_floor():
    m = MarketRange(100_000, 120_000, 140_000)
    s = suggest_remote(market_destination=m, brazil_floor=40_000, user_min_remote=None, currency="USD", discount=0.6)
    assert s.target == 60_000
    s2 = suggest_remote(market_destination=m, brazil_floor=80_000, user_min_remote=None, currency="USD", discount=0.6)
    assert s2.target == 80_000


def test_remote_discount_is_clamped():
    m = MarketRange(100_000, 120_000, 140_000)
    s = suggest_remote(market_destination=m, brazil_floor=0, user_min_remote=None, currency="USD", discount=0.1)
    assert s.inputs["discount"] == 0.5


def test_market_from_histogram_percentiles():
    hist = {"40000": 5, "50000": 10, "60000": 20, "70000": 10, "80000": 5}
    m = market_from_histogram(hist)
    assert (m.p25, m.p50, m.p75) == (50_000, 60_000, 70_000)


def test_market_from_histogram_needs_enough_data():
    assert market_from_histogram({"50000": 3, "60000": 2}) is None


def test_round_salary():
    assert round_salary(81_437) == 81_000
    assert round_salary(81_600) == 82_000


def test_to_json_rounds_values():
    s = suggest_remote(market_destination=None, brazil_floor=55_555, user_min_remote=None, currency="USD")
    assert s.to_json()["target"] == 56_000
