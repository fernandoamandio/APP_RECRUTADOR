from recrutador.dedup import dedup_hash, deduplicate, merge, normalize_company, normalize_title
from recrutador.learning import apply_event, update_remote_discount
from recrutador.models import CareerProfile, Eligibility, RawJob
from recrutador.prefilter import prefilter
from recrutador.scoring import score
from recrutador.sponsors import SponsorRegistry, load_uk_csv


def job(**kw) -> RawJob:
    base = dict(source="x", external_id="1", url="https://e.com/1", title="Senior PL/SQL Developer",
                company="Acme Ltd", description="")
    base.update(kw)
    return RawJob(**base)


# ---------- dedup ----------

def test_normalizers():
    assert normalize_company("Acme Holdings B.V.") == "acme"
    assert normalize_title("Sr. Oracle Developer (m/f/d) - Remote") == "senior oracle developer"


def test_same_job_from_two_sources_is_merged():
    a = job(source="adzuna", external_id="a", company="Acme Ltd", country="GB", description="curta")
    b = job(source="jooble", external_id="b", company="ACME", country="GB",
            description="descrição bem mais longa", salary_min=60000, salary_max=70000, currency="GBP")
    groups = deduplicate([a, b])
    assert len(groups) == 1
    merged = merge(next(iter(groups.values())))
    assert merged.description == "descrição bem mais longa"
    assert merged.salary_min == 60000


def test_different_country_is_a_different_job():
    assert dedup_hash(job(country="GB")) != dedup_hash(job(country="NL"))


# ---------- pré-filtro ----------

def test_prefilter_blocks_citizenship_restriction():
    ok, reason = prefilter(job(description="This role is open to US citizens only."))
    assert not ok and "citizen" in reason


def test_prefilter_blocks_no_sponsorship_for_onsite():
    ok, _ = prefilter(job(is_remote=False, description="We are unable to sponsor visas for this role."))
    assert not ok


def test_prefilter_keeps_remote_even_without_sponsorship():
    ok, _ = prefilter(job(is_remote=True, description="We do not offer visa sponsorship. Work from anywhere in LATAM."))
    assert ok


# ---------- pontuação ----------

PROFILE = CareerProfile(
    target_titles=["PL/SQL Developer", "Oracle Developer"],
    stack=[{"name": "PL/SQL", "level": "main"}, {"name": "Oracle", "level": "main"}, {"name": "Python", "level": "basic"}],
    seniority="senior",
)


def test_matching_job_scores_high_with_reasons():
    j = job(description="Strong PL/SQL and Oracle 19c experience required.")
    s, reasons = score(j, PROFILE, Eligibility.REMOTE_BR)
    assert s >= 80
    assert any("PL/SQL" in r for r in reasons)


def test_unrelated_job_scores_low():
    j = job(title="Frontend Engineer", description="React and TypeScript.")
    s, _ = score(j, PROFILE, Eligibility.UNCERTAIN)
    assert s < 30


def test_learned_country_penalty_lowers_score():
    j = job(country="DE", description="PL/SQL Oracle")
    base, _ = score(j, PROFILE, Eligibility.VISA_SPONSOR)
    penalized, _ = score(j, PROFILE, Eligibility.VISA_SPONSOR, {"country:DE": -15})
    assert penalized == base - 15


# ---------- aprendizado ----------

def test_dismiss_by_country_only_penalizes_country():
    prefs = apply_event({}, "dismissed", company="Acme", country="de", reason="country")
    assert prefs == {"country:DE": -4.0}


def test_dismiss_for_salary_does_not_touch_company_or_country():
    assert apply_event({}, "dismissed", company="Acme", country="DE", reason="salary_low") == {}


def test_weights_are_capped():
    prefs = {}
    for _ in range(10):
        prefs = apply_event(prefs, "offer", company="Acme")
    assert prefs["company:acme"] == 20.0


def test_remote_discount_moves_toward_user_choice():
    # usuário pediu 80k com P25 de 100k → desconto implícito 0,8
    assert update_remote_discount(0.7, 70_000, 80_000, 100_000) == 0.73


# ---------- registro de patrocinadores ----------

def test_uk_sponsor_csv_and_lookup():
    csv_text = "Organisation Name,Town/City,County,Type & Rating,Route\nAcme Holdings Ltd,London,,Worker (A rating),Skilled Worker\n"
    reg = SponsorRegistry({"GB": load_uk_csv(csv_text)})
    assert reg.is_registered("ACME Holdings", "gb")
    assert not reg.is_registered("Acme", "NL")
