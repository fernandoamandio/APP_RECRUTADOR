from recrutador.sources import ArbeitnowSource, GetOnBoardSource, InfoJobsSource, WorkingNomadsSource
from recrutador.sources.arbeitnow import VISA_NOTE


def test_arbeitnow_filters_by_keyword_and_marks_visa():
    payload = {"data": [
        {"slug": "oracle-dev-1", "company_name": "Acme GmbH", "title": "Oracle PL/SQL Developer",
         "description": "<p>PL/SQL</p>", "remote": False, "url": "https://www.arbeitnow.com/jobs/1",
         "tags": ["Database"], "job_types": [], "location": "Berlin", "created_at": 1791924909},
        {"slug": "sales-2", "company_name": "Beta", "title": "Account Executive", "description": "Sales",
         "remote": True, "url": "https://www.arbeitnow.com/jobs/2", "tags": [], "location": "", "created_at": 1791924909},
    ]}
    [j] = ArbeitnowSource.parse(payload, ["PL/SQL Developer"], visa=True)
    assert (j.external_id, j.company, j.city, j.is_remote) == ("oracle-dev-1", "Acme GmbH", "Berlin", False)
    assert j.description.startswith(VISA_NOTE)
    assert j.published_at.year == 2026


def test_getonbrd_resolves_company_and_remote():
    payload = {"data": [{
        "id": "senior-oracle-developer-acme-remote", "type": "job",
        "attributes": {"title": "Senior Oracle Developer", "description": "<p>PL/SQL</p>", "functions": "<p>Tuning</p>",
                       "remote": True, "remote_modality": "fully_remote", "remote_zone": "LATAM",
                       "countries": ["Chile"], "min_salary": 3500, "max_salary": 4500, "published_at": 1791487303,
                       "company": {"data": {"id": 11068, "type": "company"}}},
        "links": {"public_url": "https://www.getonbrd.com/jobs/senior-oracle-developer-acme-remote"},
    }]}
    names = {"11068": "Acme"}
    [j] = GetOnBoardSource.parse(payload, lambda cid: names[cid])
    assert (j.company, j.is_remote, j.country) == ("Acme", True, None)  # remota: sem país fixo
    assert (j.salary_min, j.salary_period, j.currency) == (3500, "month", "USD")
    assert "zona remota: LATAM" in j.description and "Tuning" in j.description


def test_getonbrd_onsite_maps_country():
    payload = {"data": [{"id": "x", "attributes": {"title": "DBA", "remote": False, "remote_modality": "no_remote",
                                                    "countries": ["Chile"], "company": {"data": {"id": 1}}},
                         "links": {"public_url": "u"}}]}
    [j] = GetOnBoardSource.parse(payload, lambda cid: "Acme")
    assert j.country == "CL"


def test_workingnomads_parses_list_and_filters():
    payload = [
        {"url": "https://www.workingnomads.com/job/go/1938564/", "title": "Senior Oracle Developer",
         "description": "<p>PL/SQL</p>", "company_name": "Lemon.io", "category_name": "Development",
         "tags": "oracle,sql", "location": "Europe, LATAM", "pub_date": "2026-10-13T06:06:11-04:00"},
        {"url": "https://www.workingnomads.com/job/go/2/", "title": "Designer", "description": "Figma",
         "company_name": "Beta", "tags": "figma", "location": "USA", "pub_date": "2026-10-13T06:06:11-04:00"},
    ]
    [j] = WorkingNomadsSource.parse(payload, ["PL/SQL Developer", "oracle"])
    assert (j.external_id, j.is_remote, j.tags) == ("1938564", True, ["oracle", "sql"])
    assert j.description.startswith("Regiões aceitas: Europe, LATAM")


def test_infojobs_parse():
    payload = {"offers": [{"id": "abc123", "title": "Desarrollador PL/SQL", "author": {"id": "9", "name": "Acme SL"},
                           "city": "Madrid", "province": {"id": 33, "value": "Madrid"},
                           "link": "https://www.infojobs.net/madrid/desarrollador/of-iabc123",
                           "teleworking": {"id": 2, "value": "Solo teletrabajo"},
                           "requirementMin": "Experiencia con Oracle", "published": "2026-10-12T10:00:00.000Z"}]}
    [j] = InfoJobsSource.parse(payload)
    assert (j.country, j.company, j.is_remote) == ("ES", "Acme SL", True)
    assert "Experiencia con Oracle" in j.description
