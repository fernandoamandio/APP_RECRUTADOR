"""Descobre o país (ISO 3166-1) a partir do texto de localização que as fontes devolvem.

Ex.: "United States" -> US, "Austin, TX" -> US, "São Paulo, SP" -> BR, "London, UK" -> GB.
Quando o texto cita vários países ("Europe, LATAM, USA") ou nenhum, devolve None:
é uma vaga multi-região/remota e não pertence a um país só.
"""

from __future__ import annotations

import re
import unicodedata

# Nomes e apelidos de países (sem acento, minúsculos)
_COUNTRY_ALIASES = {
    "BR": ["brasil", "brazil", "br"],
    "US": ["united states", "united states of america", "usa", "us", "estados unidos", "eua", "u.s.", "u.s.a."],
    "GB": ["united kingdom", "uk", "u.k.", "england", "scotland", "wales", "great britain", "reino unido", "gb"],
    "CA": ["canada", "canadá"],
    "DE": ["germany", "deutschland", "alemanha", "de"],
    "NL": ["netherlands", "the netherlands", "holland", "holanda", "paises baixos", "nederland", "nl"],
    "ES": ["spain", "espana", "espanha", "es"],
    "PT": ["portugal", "pt"],
    "FR": ["france", "franca", "fr"],
    "IE": ["ireland", "irlanda", "ie"],
    "IT": ["italy", "italia"],
    "PL": ["poland", "polska", "polonia"],
    "CH": ["switzerland", "suica", "schweiz"],
    "AT": ["austria", "osterreich"],
    "BE": ["belgium", "belgica"],
    "SE": ["sweden", "suecia"],
    "DK": ["denmark", "dinamarca"],
    "NO": ["norway", "noruega"],
    "FI": ["finland", "finlandia"],
    "AU": ["australia"],
    "NZ": ["new zealand", "nova zelandia"],
    "IN": ["india"],
    "SG": ["singapore", "singapura"],
    "MX": ["mexico"],
    "AR": ["argentina"],
    "CL": ["chile"],
    "CO": ["colombia"],
    "PE": ["peru"],
    "UY": ["uruguay", "uruguai"],
    "ZA": ["south africa", "africa do sul"],
}

# Cidades frequentes nas vagas (sem acento, minúsculas)
_CITIES = {
    "BR": ["sao paulo", "rio de janeiro", "campinas", "belo horizonte", "curitiba", "porto alegre", "recife",
           "florianopolis", "brasilia", "salvador", "fortaleza", "goiania", "barueri", "sao jose dos campos",
           "ribeirao preto", "sorocaba", "jundiai", "santos", "manaus", "belem", "vitoria", "londrina", "joinville"],
    "US": ["new york", "san francisco", "los angeles", "seattle", "austin", "chicago", "boston", "atlanta",
           "dallas", "houston", "denver", "miami", "phoenix", "san diego", "san jose", "washington, dc"],
    "GB": ["london", "manchester", "birmingham", "edinburgh", "glasgow", "leeds", "bristol", "cambridge", "oxford"],
    "DE": ["berlin", "munich", "munchen", "hamburg", "frankfurt", "cologne", "koln", "stuttgart", "dusseldorf"],
    "NL": ["amsterdam", "rotterdam", "the hague", "den haag", "utrecht", "eindhoven"],
    "CA": ["toronto", "vancouver", "montreal", "calgary", "ottawa"],
    "ES": ["madrid", "barcelona", "valencia", "sevilla", "malaga", "bilbao"],
    "PT": ["lisbon", "lisboa", "porto"],
    "IE": ["dublin"],
    "FR": ["paris", "lyon"],
}

# Siglas de estados: "Austin, TX" / "Campinas, SP"
_US_STATES = ("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY "
              "NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC").split()
_BR_STATES = "AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split()
# Siglas que existem nos dois países: só contam com outra pista
_AMBIGUOUS_STATES = set(_US_STATES) & set(_BR_STATES)

# Termos que indicam multi-região: o texto não pertence a um país só
_MULTI_REGION = re.compile(r"\b(worldwide|anywhere|global|europe|emea|latam|latin america|americas|apac|"
                           r"north america|south america|eu)\b")


def _ascii(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()


def _find(text: str, terms: list[str]) -> bool:
    return any(re.search(rf"(?<![a-z0-9]){re.escape(t)}(?![a-z0-9])", text) for t in terms)


def infer_country(location: str | None) -> str | None:
    if not location or not location.strip():
        return None
    raw = location.strip()
    text = _ascii(raw)

    found: set[str] = set()
    for code, aliases in _COUNTRY_ALIASES.items():
        # Siglas de 2 letras ("us", "de", "es", "pt", "br"...) só valem como palavra isolada no fim
        # ("Berlin, DE"), para não confundir com preposições em espanhol/português
        long_aliases = [a for a in aliases if len(a) > 2]
        short = [a for a in aliases if len(a) <= 2]
        if _find(text, long_aliases) or any(re.search(rf",\s*{a}\s*$", text) for a in short):
            found.add(code)
    for code, cities in _CITIES.items():
        if _find(text, cities):
            found.add(code)

    # "Austin, TX" (EUA) / "Campinas, SP" (Brasil)
    # Só quando nenhuma outra pista apareceu ("Berlin, DE" não é Delaware)
    m = re.search(r",\s*([A-Z]{2})\s*(?:,|$)", raw) if not found else None
    if m:
        st = m.group(1)
        if st in _AMBIGUOUS_STATES:
            pass  # ex.: "PA", "MA", "SC": decide pelas outras pistas
        elif st in _US_STATES:
            found.add("US")
        elif st in _BR_STATES:
            found.add("BR")

    if len(found) == 1:
        return found.pop()
    if not found and _MULTI_REGION.search(text):
        return None
    return None  # nenhum país ou vários países: multi-região
