from recrutador.geo import infer_country


def test_country_names():
    assert infer_country("United States") == "US"
    assert infer_country("Remote - USA") == "US"
    assert infer_country("Reino Unido") == "GB"
    assert infer_country("Amsterdam, Netherlands") == "NL"
    assert infer_country("São Paulo, Estado de São Paulo, BR") == "BR"


def test_cities_and_states():
    assert infer_country("Austin, TX") == "US"
    assert infer_country("Campinas, SP") == "BR"
    assert infer_country("London") == "GB"
    assert infer_country("Berlin, DE") == "DE"
    assert infer_country("Florianópolis") == "BR"


def test_multi_region_or_unknown_is_none():
    assert infer_country("Europe, LATAM, APAC, the U.S., Canada") is None
    assert infer_country("Anywhere in the World") is None
    assert infer_country("Remote") is None
    assert infer_country("") is None
    assert infer_country(None) is None


def test_two_letter_words_do_not_trigger():
    # "de", "es", "pt" no meio do texto são preposições, não países
    assert infer_country("Remoto de qualquer lugar") is None
