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


def test_scope_country_for_jobs_without_location():
    items = [{"site": "indeed", "title": "DBA", "job_url": "u1", "location": "", "is_remote": False},
             {"site": "indeed", "title": "DBA", "job_url": "u2", "location": "", "is_remote": True}]
    onsite, remote = ApifyJobsSource.parse(items, scope_country="BR")
    assert onsite.country == "BR" and remote.country == "BR"
    [abroad] = ApifyJobsSource.parse(items[1:], scope_country=None)
    assert abroad.country is None


def test_location_as_dict():
    items = [{"site": "linkedin", "title": "DBA", "job_url": "u", "location": {"city": "Berlin", "country": "Germany"}}]
    [j] = ApifyJobsSource.parse(items, scope_country=None)
    assert j.country == "DE" and j.city == "Berlin, Germany"


class _Resp:
    def __init__(self, data):
        self.data = data

    def raise_for_status(self):
        pass

    def json(self):
        return self.data


class _FakeApify:
    """Simula a API da Apify: cada execução devolve `per_site` vagas por site."""

    def __init__(self):
        self.payloads = []

    def post(self, url, params=None, headers=None, json=None, timeout=None):
        self.payloads.append(json)
        return _Resp({"data": {"id": str(len(self.payloads)), "status": "SUCCEEDED",
                               "defaultDatasetId": str(len(self.payloads))}})

    def get(self, url, params=None, headers=None, timeout=None):
        p = self.payloads[int(url.split("/")[-2]) - 1]
        loc = "São Paulo, Brazil" if p["location"] == "Brazil" else "Remote, Germany"
        items = [{"site": site, "title": f"{p['searchTerm']} {i}", "location": loc, "is_remote": p["isRemote"],
                  "job_url": f"{site}/{p['searchTerm']}/{p['location']}/{i}", "date_posted": f"2026-10-{10 + i:02d}"}
                 for site in p["sites"] for i in range(p["maxResults"])]
        # uma vaga brasileira "vazando" na busca remota: não pode entrar nas 15 de outros países
        if p["isRemote"]:
            items.append({"site": "linkedin", "title": "BR remota", "location": "Brazil", "job_url": "x/br",
                          "is_remote": True})
        return _Resp(items)


def test_budget_split_brazil_and_abroad():
    fake = _FakeApify()
    src = ApifyJobsSource(fake, "t", br_results=5, remote_results=15)
    jobs = src.fetch(["PL/SQL Developer", "Oracle Developer", "ignorado"], [])
    br = [j for j in jobs if j.country == "BR"]
    abroad = [j for j in jobs if j.country != "BR"]
    assert len(br) == 5 and len(abroad) == 15
    assert len(fake.payloads) == 4  # 2 termos x 2 escopos
    assert [p["maxResults"] for p in fake.payloads] == [2, 2, 4, 4]  # 5 e 15 com folga de 50%
    dates = [j.published_at for j in abroad]
    assert dates == sorted(dates, reverse=True)  # mais recentes primeiro
