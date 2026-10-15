from recrutador.sources import ApifyJobsSource


def test_parse_jobspy_items():
    items = [
        {"site": "linkedin", "id": "li-1", "title": "Senior PL/SQL Developer", "company": "Acme",
         "location": "São Paulo, SP, BR", "job_url": "https://www.linkedin.com/jobs/view/1", "is_remote": False,
         "date_posted": "2026-10-14", "description": "Oracle **PL/SQL**", "salary_min": 15000, "salary_max": 20000,
         "salary_currency": "BRL", "salary_interval": "monthly"},
        {"site": "indeed", "title": "Oracle Developer", "company": "Beta", "location": "Austin, TX",
         "job_url": "https://www.indeed.com/viewjob?jk=2", "is_remote": True, "date_posted": None,
         "description": "<p>PL/SQL</p>"},
        {"site": "glassdoor", "title": "", "job_url": "x"},  # sem título: ignorada
    ]
    a, b = ApifyJobsSource.parse(items, scope_country="BR")
    assert (a.source, a.country, a.salary_period, a.currency) == ("linkedin", "BR", "month", "BRL")
    assert a.published_at.year == 2026
    assert (b.source, b.country, b.is_remote, b.description) == ("indeed", "US", True, "PL/SQL")
    assert b.external_id  # gerado pelo hash do link


def test_scope_country_only_for_onsite_without_location():
    items = [{"site": "indeed", "title": "DBA", "job_url": "u1", "location": "", "is_remote": False},
             {"site": "indeed", "title": "DBA", "job_url": "u2", "location": "", "is_remote": True}]
    onsite, remote = ApifyJobsSource.parse(items, scope_country="BR")
    assert onsite.country == "BR" and remote.country is None


def test_location_as_dict():
    items = [{"site": "linkedin", "title": "DBA", "job_url": "u", "location": {"city": "Berlin", "country": "Germany"}}]
    [j] = ApifyJobsSource.parse(items, scope_country=None)
    assert j.country == "DE" and j.city == "Berlin, Germany"
