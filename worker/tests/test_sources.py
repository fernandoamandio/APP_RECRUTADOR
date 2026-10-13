from recrutador.sources import AdzunaSource, JoobleSource, RemoteOKSource, WeWorkRemotelySource


def test_remoteok_skips_legal_notice_and_filters_by_tag():
    payload = [
        {"legal": "API Terms of Service: Please link back..."},
        {"id": "1", "position": "Senior Oracle DBA", "company": "Acme", "tags": ["oracle", "sql"],
         "description": "<p>PL/SQL</p>", "url": "https://remoteok.com/remote-jobs/1", "date": "2026-10-10T10:00:00+00:00",
         "salary_min": 90000, "salary_max": 120000},
        {"id": "2", "position": "React Developer", "company": "Beta", "tags": ["react"], "description": ""},
    ]
    jobs = RemoteOKSource.parse(payload, tags=["oracle"], search_terms=["PL/SQL Developer"])
    assert [j.external_id for j in jobs] == ["1"]
    assert jobs[0].description == "PL/SQL"
    assert jobs[0].currency == "USD" and jobs[0].is_remote


def test_adzuna_parse():
    payload = {"results": [{"id": 42, "title": "PL/SQL Developer", "company": {"display_name": "Acme"},
                            "location": {"display_name": "Amsterdam"}, "description": "Oracle <b>PL/SQL</b>",
                            "redirect_url": "https://adzuna.example/42", "salary_min": 70000, "salary_max": 80000,
                            "created": "2026-10-11T08:00:00Z"}]}
    [j] = AdzunaSource.parse(payload, "nl")
    assert (j.country, j.currency, j.salary_period) == ("NL", "EUR", "year")
    assert j.description == "Oracle PL/SQL"


def test_jooble_parse_marks_remote():
    payload = {"jobs": [{"id": 7, "title": "Oracle Developer", "company": "Acme", "location": "Remote",
                         "snippet": "PL/SQL &amp; Oracle", "link": "https://jooble.example/7"}]}
    [j] = JoobleSource.parse(payload)
    assert j.is_remote and j.description == "PL/SQL & Oracle"


def test_wwr_parse_splits_company_and_filters():
    rss = """<?xml version="1.0"?><rss><channel>
      <item><title>Acme: Senior PL/SQL Developer</title><region>Anywhere in the World</region>
        <link>https://weworkremotely.com/remote-jobs/acme-1</link><guid>acme-1</guid>
        <description>&lt;p&gt;Oracle and PL/SQL&lt;/p&gt;</description><pubDate>Fri, 10 Oct 2026 12:00:00 +0000</pubDate></item>
      <item><title>Beta: Designer</title><link>https://weworkremotely.com/remote-jobs/beta-2</link>
        <description>Figma</description></item>
    </channel></rss>"""
    jobs = WeWorkRemotelySource.parse(rss, ["PL/SQL Developer", "oracle"])
    assert len(jobs) == 1
    assert (jobs[0].company, jobs[0].title, jobs[0].city) == ("Acme", "Senior PL/SQL Developer", "Anywhere in the World")
