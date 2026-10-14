from recrutador.profile_extract import PROFILE_TOOL, to_career_profile_row


def test_profile_row_maps_keywords():
    p = {"target_titles": ["PL/SQL Developer"], "seniority": "senior", "stack": [{"name": "Oracle", "level": "main"}],
         "search_terms": ["PL/SQL Developer"], "remoteok_tags": ["oracle"], "strengths": ["x"], "gaps": []}
    row = to_career_profile_row("u1", "d1", p)
    assert row["keywords"] == {"search_terms": ["PL/SQL Developer"], "remoteok_tags": ["oracle"]}
    assert row["source_doc_id"] == "d1" and row["domains"] == []


def test_profile_row_tolerates_missing_fields():
    row = to_career_profile_row("u1", "d1", {})
    assert row["target_titles"] == [] and row["seniority"] is None


def test_tool_requires_search_terms():
    assert "search_terms" in PROFILE_TOOL["input_schema"]["required"]
