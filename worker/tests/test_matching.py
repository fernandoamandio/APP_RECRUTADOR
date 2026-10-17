from recrutador.matching import CandidateMaterial, job_as_text, parse_match, profile_as_text
from recrutador.models import Eligibility, RawJob
from recrutador.prefilter import prefilter
from recrutador.sponsors import SponsorRegistry
from recrutador.triage import triage


def test_parse_match_clamps_and_trims():
    r = parse_match({"match_percent": 112.4, "strengths": ["PL/SQL avançado", " ", "Oracle 19c", "Tuning", "extra"],
                     "gaps": ["AWS"]})
    assert r.percent == 100
    assert r.strengths == ["PL/SQL avançado", "Oracle 19c", "Tuning"]
    assert r.gaps == ["AWS"]


def test_candidate_with_pdfs_caches_last_document():
    c = CandidateMaterial(cv_pdf=b"%PDF-cv", cover_letter_pdf=b"%PDF-cl", profile_text="x")
    blocks = c.content_blocks()
    assert [b["type"] for b in blocks] == ["document", "document"]
    assert [b["title"] for b in blocks] == ["Currículo", "Cover letter"]
    assert "cache_control" in blocks[-1] and "cache_control" not in blocks[0]
    assert c.source == "cv+cover_letter"


def test_candidate_without_pdfs_uses_profile_text():
    c = CandidateMaterial(profile_text=profile_as_text({"target_titles": ["PL/SQL Developer"], "stack": [],
                                                        "seniority": "senior"}))
    [block] = c.content_blocks()
    assert block["type"] == "text" and "PL/SQL Developer" in block["text"]
    assert c.source == "profile"


def test_job_as_text_includes_location():
    j = RawJob(source="x", external_id="1", url="", title="DBA", company="Acme", city="Campinas", country="BR",
               description="Oracle")
    assert "Local: Campinas, BR" in job_as_text(j)


def test_brazilian_job_is_local_without_calling_claude():
    j = RawJob(source="jooble", external_id="1", url="", title="Desenvolvedor PL/SQL", company="Acme",
               city="Campinas, SP", country="BR")
    r = triage(None, j, SponsorRegistry({}))  # sem IA: a regra do país decide sem chamar o modelo
    assert r.category is Eligibility.LOCAL_BR and r.confidence == 1.0


def test_prefilter_keeps_brazilian_onsite_job_without_sponsorship():
    j = RawJob(source="x", external_id="1", url="", title="DBA", company="Acme", country="BR", is_remote=False,
               description="We do not offer visa sponsorship.")
    assert prefilter(j)[0]
