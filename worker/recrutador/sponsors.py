"""Registros oficiais de empresas autorizadas a patrocinar visto (Reino Unido e Holanda).

- Reino Unido: "Register of licensed sponsors: workers" (CSV publicado no GOV.UK).
- Holanda: "Public register recognised sponsors" do IND (atualizado mensalmente).

Os arquivos são baixados por um job separado e carregados na tabela sponsor_registry.
Estar no registro indica que a empresa PODE patrocinar; não garante patrocínio para a vaga.
"""

from __future__ import annotations

import csv
import io

from .dedup import normalize_company


def load_uk_csv(text: str) -> set[str]:
    reader = csv.DictReader(io.StringIO(text))
    name_col = next((c for c in reader.fieldnames or [] if "organisation" in c.lower()), None)
    if not name_col:
        raise ValueError("coluna de organização não encontrada no CSV do Reino Unido")
    return {normalize_company(row[name_col]) for row in reader if row.get(name_col)}


class SponsorRegistry:
    def __init__(self, by_country: dict[str, set[str]]):
        self.by_country = {k.upper(): v for k, v in by_country.items()}

    def is_registered(self, company: str, country: str | None) -> bool:
        if not country or country.upper() not in self.by_country:
            return False
        return normalize_company(company) in self.by_country[country.upper()]
