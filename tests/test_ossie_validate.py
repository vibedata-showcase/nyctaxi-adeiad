"""Tests for tools/ossie.py validate (core + VIBEDATA second pass)."""

import json
import sys
from pathlib import Path

import yaml
from typer.testing import CliRunner

SKILL_SCRIPTS = Path(__file__).resolve().parent.parent / ".agents" / "skills" / "semantic-model" / "scripts"
sys.path.insert(0, str(SKILL_SCRIPTS))

from ossie import app  # noqa: E402

RUNNER = CliRunner()
CANONICAL = Path("logical-model/nyc_taxi_analytics.ossie.yaml")


def _doc():
    return yaml.safe_load(CANONICAL.read_text())


def _write(tmp_path, doc):
    target = tmp_path / "m.ossie.yaml"
    target.write_text(yaml.safe_dump(doc))
    return target


def _run(*args):
    result = RUNNER.invoke(app, list(args))
    assert result.exit_code in (0, 1, 2), result.output
    parsed = json.loads(result.stdout or "[]")  # stdout is always pure JSON
    return result.exit_code, parsed


def _codes(diags):
    return {(d.get("code"), d["severity"]) for d in diags}


def test_canonical_validates():
    """Structural gate only: the canonical model parses and resolves."""
    code, diags = _run("validate", str(CANONICAL))
    assert code == 0, diags
    assert not [d for d in diags if d["severity"] == "error"]
    assert ("vibedata/table-unjoined", "warning") not in _codes(diags)  # every physical table is joined once the bridge leaves the model


def test_missing_file_stdout_stays_json():
    code, diags = _run("validate", "nope_nonexistent.yaml")
    assert code == 1
    assert ("cli/unreadable", "error") in _codes(diags)


def test_empty_dir_stdout_stays_json(tmp_path):
    code, diags = _run("validate", str(tmp_path))
    assert code == 1
    assert ("cli/no-files", "error") in _codes(diags)


def test_dangling_alias_fails(tmp_path):
    doc = _doc()
    doc["custom_extensions"][0]["data"] = json.dumps({
        "vibedata_version": "1.0",
        "physical_tables": [{"name": "Ghost", "source": "core.x",
                             "table_type": "ALIAS", "alias_of": "Nope"}],
        "physical_joins": []})
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/alias-dangling", "error") in _codes(diags)


def test_self_alias_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["custom_extensions"][0]["data"])
    next(
        table for table in payload["physical_tables"] if table["name"] == "Pickup_Zone"
    )["alias_of"] = "Pickup_Zone"
    doc["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/alias-dangling", "error") in _codes(diags)


def test_dangling_lts_table_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][0]["physical_table"] = "Nope"
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/lts-dangling-table", "error") in _codes(diags)


def test_unknown_column_map_key_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][0]["column_map"]["nope_col"] = "nope_col"
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/lts-unknown-field", "error") in _codes(diags)


def test_unknown_vibedata_key_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logicl_sources_typo"] = payload.pop("logical_sources")
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/unknown-key", "error") in _codes(diags)


def test_bad_cardinality_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["relationships"][0]["custom_extensions"][0]["data"])
    payload["cardinality"] = "sometimes"
    doc["relationships"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-cardinality", "error") in _codes(diags)


def test_bad_physical_join_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["relationships"][0]["custom_extensions"][0]["data"])
    payload["physical_join"] = "nonexistent_join"
    doc["relationships"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/join-dangling", "error") in _codes(diags)


def test_non_json_data_fails(tmp_path):
    doc = _doc()
    doc["datasets"][0]["custom_extensions"][0]["data"] = "{nope"
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/data-not-json", "error") in _codes(diags)


def test_malformed_shapes_do_not_crash(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][2]["custom_extensions"][0]["data"])
    payload["hierarchies"] = ["not-a-dict"]
    payload["scd"] = "type2"
    payload["logical_sources"] = [{"name": "x"}]
    doc["datasets"][2]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    codes = _codes(diags)
    assert ("vibedata/hierarchy-not-object", "error") in codes
    assert ("vibedata/scd-not-object", "error") in codes
    assert ("vibedata/lts-dangling-table", "error") in codes
    assert not any(d.get("code") == "cli/check-crashed" for d in diags)


def test_scd_bad_type_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][2]["custom_extensions"][0]["data"])
    payload["scd"]["type"] = 7
    doc["datasets"][2]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/scd-bad-type", "error") in _codes(diags)


def test_partitioned_by_lives_on_the_physical_table(tmp_path):
    """Partitioning is physical: a physical table may declare it, a logical dataset may not."""
    doc = _doc()
    model = _payload(doc)
    model["physical_tables"][0]["partitioned_by"] = ["pickup_date"]
    _set_payload(doc, model)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0, diags
    model["physical_tables"][0]["partitioned_by"] = "pickup_date"
    _set_payload(doc, model)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-partitioned-by", "error") in _codes(diags)
    doc = _doc()
    trips = _named(doc["datasets"], "trips")
    payload = _payload(trips)
    payload["partitioned_by"] = ["pickup_date"]
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/unknown-key", "error") in _codes(diags)


def test_duplicate_dataset_fails_upstream(tmp_path):
    doc = _doc()
    doc["datasets"].append(dict(doc["datasets"][0]))
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert any(d["severity"] == "error" and "Duplicate dataset" in d["message"]
               for d in diags)


def test_hierarchy_unknown_level_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][1]["custom_extensions"][0]["data"])
    payload["hierarchies"][0]["levels"].append("nope_level")
    doc["datasets"][1]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/hierarchy-unknown-level", "error") in _codes(diags)


def test_checker_keys_match_schema():
    """Skill checker allowlists and vibedata-schema.json agree."""
    import ossie_vibedata as v
    schema = json.loads((SKILL_SCRIPTS / "vibedata-schema.json").read_text())
    defs = schema["$defs"]
    pairs = [(v.MODEL_KEYS, "modelPayload"), (v.DATASET_KEYS, "datasetPayload"),
             (v.RELATIONSHIP_KEYS, "relationshipPayload"),
             (v.PHYSICAL_TABLE_KEYS, "physicalTable"),
             (v.PHYSICAL_JOIN_KEYS, "physicalJoin"), (v.LTS_KEYS, "logicalSource"),
             (v.HIERARCHY_KEYS, "hierarchy"), (v.SCD_KEYS, "scd"),
             (v.LEVEL_KEYS, "level"),
             (v.LEVEL_REF_KEYS, "levelRef"), (v.METRIC_KEYS, "metricPayload"),
             (v.TIME_SERIES_KEYS, "timeSeries"), (v.BASED_ON_KEYS, "basedOnDimensions"),
             (v.LEVEL_KEY_KEYS, "levelKey"), (v.ROW_LEVEL_KEYS, "rowLevel")]
    for keys, ref in pairs:
        assert keys == set(defs[ref]["properties"]), ref


def test_version_consistent_and_present(tmp_path):
    doc = _doc()
    code, _ = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["vibedata_version"] = "9.9"
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/version-mismatch", "error") in _codes(diags)
    del payload["vibedata_version"]
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/version-missing", "error") in _codes(diags)


def test_note_keys_accepted(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][1]["note"] = (
        "billable_revenue refused: agg sums unfiltered totals; content_filter held by "
        "assert_semantic_content_holds")
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    model_payload = json.loads(doc["custom_extensions"][0]["data"])
    model_payload["physical_tables"][0]["note"] = "detail grain base table"
    doc["custom_extensions"][0]["data"] = json.dumps(model_payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0
    assert not [d for d in diags if d["severity"] == "error"]


def test_from_column_unknown_fails(tmp_path):
    doc = _doc()
    doc["relationships"][0]["from_columns"] = ["no_such_field"]
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("relationship/from-column-unknown", "error") in _codes(diags)


def test_crossdoc_diverged_dataset_fails(tmp_path):
    doc = _doc()
    twin = _doc()
    twin["name"] = "twin_model"
    twin["datasets"][1]["source"] = "core.dim_date_other"
    _write(tmp_path, doc)
    (tmp_path / "twin.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(tmp_path))
    assert code == 1
    assert ("crossdoc/diverged", "error") in _codes(diags)


def test_crossdoc_identical_copy_passes(tmp_path):
    doc = _doc()
    twin = _doc()
    twin["name"] = "twin_model"
    _write(tmp_path, doc)
    (tmp_path / "twin.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(tmp_path))
    assert code == 0, [d for d in diags if d["severity"] == "error"]


def test_crossdoc_diverged_metric_fails(tmp_path):
    doc = _doc()
    twin = _doc()
    twin["name"] = "twin_model"
    twin["metrics"][0]["expression"]["dialects"][0]["expression"] = "COUNT(*)"
    _write(tmp_path, doc)
    (tmp_path / "twin.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(tmp_path))
    assert code == 1
    assert ("crossdoc/diverged", "error") in _codes(diags)


def test_empty_column_map_tombstone_with_note_passes(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][1]["column_map"] = {}
    payload["logical_sources"][1]["note"] = (
        "withdrawn: agg built on the old billable rule; re-add when rebuilt")
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0, [d for d in diags if d["severity"] == "error"]


def test_crossdoc_identical_identity_with_local_roles_passes(tmp_path):
    """Copies must share identity; role-specific logical sources stay local."""
    doc = _doc()
    twin = _doc()
    twin["name"] = "twin_model"
    zone = json.loads(twin["datasets"][2]["custom_extensions"][0]["data"])
    zone["logical_sources"] = [s for s in zone["logical_sources"]
                               if "role" not in s["name"]]
    twin["datasets"][2]["custom_extensions"][0]["data"] = json.dumps(zone)
    _write(tmp_path, doc)
    (tmp_path / "twin.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(tmp_path))
    assert code == 0, [d for d in diags if d["severity"] == "error"]


def test_example_star_validates():
    example = SKILL_SCRIPTS.parent / "examples" / "star.ossie.yaml"
    code, diags = _run("validate", str(example))
    assert code == 0, [d for d in diags if d["severity"] == "error"]


def test_coverage_reports_unmapped(tmp_path):
    model = tmp_path / "model"
    marts = tmp_path / "marts"
    model.mkdir()
    marts.mkdir()
    _write(model, _doc())
    (marts / "fct_trip.sql").write_text("select 1")
    result = RUNNER.invoke(app, ["coverage", str(model), str(marts)])
    assert result.exit_code == 1
    codes = {d.get("code") for d in json.loads(result.stdout)}
    assert "coverage/phantom" in codes  # the sample doc names models absent from marts


def test_crossdoc_diverged_scd_fails(tmp_path):
    doc = _doc()
    twin = _doc()
    twin["name"] = "twin_model"
    zone = json.loads(twin["datasets"][2]["custom_extensions"][0]["data"])
    zone["scd"]["open_ended_value"] = "9999-12-31"
    twin["datasets"][2]["custom_extensions"][0]["data"] = json.dumps(zone)
    _write(tmp_path, doc)
    (tmp_path / "twin.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(tmp_path))
    assert code == 1
    assert ("crossdoc/diverged", "error") in _codes(diags)


def test_unmatched_file_in_model_dir_fails(tmp_path):
    _write(tmp_path, _doc())
    (tmp_path / "stray.ossie.yml").write_text("version: '0.2.0.dev0'\nname: x\n")
    code, diags = _run("validate", str(tmp_path))
    assert code == 1
    assert ("cli/unmatched-file", "error") in _codes(diags)


def test_to_column_unknown_fails(tmp_path):
    doc = _doc()
    doc["relationships"][0]["to_columns"] = ["not_a_field"]
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("relationship/to-column-unknown", "error") in _codes(diags)


def test_primary_key_unknown_field_fails(tmp_path):
    doc = _doc()
    doc["datasets"][0]["primary_key"] = ["no_such_key"]
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-key-column", "error") in _codes(diags)


def test_dataset_without_logical_source_fails(tmp_path):
    doc = _doc()
    payload = json.loads(doc["datasets"][1]["custom_extensions"][0]["data"])
    payload["logical_sources"] = []
    doc["datasets"][1]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/lts-empty", "error") in _codes(diags)


def test_suppliers_reports_unsupplied_metric(tmp_path):
    model = tmp_path / "model"
    model.mkdir()
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][0]["column_map"].pop("fare_residual_total", None)
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    (model / "m.ossie.yaml").write_text(yaml.safe_dump(doc))
    result = RUNNER.invoke(app, ["suppliers", str(model)])
    assert result.exit_code == 1
    assert "suppliers/metric" in result.stdout


def _notes_doc(tmp_path, note):
    model = tmp_path / "model"
    model.mkdir()
    doc = _doc()
    for dataset in doc["datasets"]:
        payload = json.loads(dataset["custom_extensions"][0]["data"])
        for source in payload["logical_sources"]:
            source.pop("note", None)
        dataset["custom_extensions"][0]["data"] = json.dumps(payload)
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][0]["note"] = note
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    (model / "m.ossie.yaml").write_text(yaml.safe_dump(doc))
    return model


def test_notes_resolves_test_and_adr(tmp_path):
    model = _notes_doc(tmp_path, "reconciliation held by assert_ok, rule ADR 0003")
    tests = tmp_path / "tests"
    tests.mkdir()
    (tests / "assert_ok.sql").write_text("select 1")
    adrs = tmp_path / "adr"
    adrs.mkdir()
    (adrs / "0003-a.md").write_text("x")
    result = RUNNER.invoke(app, ["notes", str(model), str(tests), str(adrs)])
    assert result.exit_code == 0, result.stdout


def test_notes_flags_dangling_test(tmp_path):
    model = _notes_doc(tmp_path, "reconciliation held by assert_missing")
    tests = tmp_path / "tests"
    tests.mkdir()
    adrs = tmp_path / "adr"
    adrs.mkdir()
    result = RUNNER.invoke(app, ["notes", str(model), str(tests), str(adrs)])
    assert result.exit_code == 1
    assert "notes/dangling-test" in result.stdout


def test_notes_flags_dangling_adr(tmp_path):
    model = _notes_doc(tmp_path, "floored per ADR 9999")
    tests = tmp_path / "tests"
    tests.mkdir()
    adrs = tmp_path / "adr"
    adrs.mkdir()
    result = RUNNER.invoke(app, ["notes", str(model), str(tests), str(adrs)])
    assert result.exit_code == 1
    assert "notes/dangling-adr" in result.stdout


def test_notes_ignores_plain_prose(tmp_path):
    model = _notes_doc(tmp_path, "checked against the mart SQL and the seed ranges")
    tests = tmp_path / "tests"
    tests.mkdir()
    adrs = tmp_path / "adr"
    adrs.mkdir()
    result = RUNNER.invoke(app, ["notes", str(model), str(tests), str(adrs)])
    assert result.exit_code == 0, result.stdout


def test_where_key_is_now_unknown(tmp_path):
    """`where` was removed from the key set: a stale document fails loudly."""
    doc = _doc()
    payload = json.loads(doc["datasets"][0]["custom_extensions"][0]["data"])
    payload["logical_sources"][0]["where"] = "old style population prose"
    doc["datasets"][0]["custom_extensions"][0]["data"] = json.dumps(payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/unknown-key", "error") in _codes(diags)


def test_notes_survives_malformed_payload(tmp_path):
    model = tmp_path / "model"
    model.mkdir()
    doc = _doc()
    doc["datasets"][0]["custom_extensions"][0]["data"] = '["not", "an", "object"]'
    (model / "m.ossie.yaml").write_text(yaml.safe_dump(doc))
    tests = tmp_path / "tests"
    tests.mkdir()
    adrs = tmp_path / "adr"
    adrs.mkdir()
    result = RUNNER.invoke(app, ["notes", str(model), str(tests), str(adrs)])
    assert result.exit_code in (0, 1)
    json.loads(result.stdout)  # stdout stays pure JSON


def _payload(node):
    return json.loads(node["custom_extensions"][0]["data"])


def _set_payload(node, payload):
    node["custom_extensions"][0]["data"] = json.dumps(payload)


def _named(items, name):
    return next(item for item in items if item["name"] == name)


def _trips_source(doc, source_name):
    trips = _named(doc["datasets"], "trips")
    payload = _payload(trips)
    return trips, payload, _named(payload["logical_sources"], source_name)


def test_level_needs_keys(tmp_path):
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    del payload["levels"][0]["keys"]
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-keys-missing", "error") in _codes(diags)


def test_level_needs_exactly_one_primary_key(tmp_path):
    """The primary key is what joins and blends at the level, so there is exactly one."""
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    month = _named(payload["levels"], "month")
    _named(month["keys"], "year_month")["primary"] = True
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-primary-key", "error") in _codes(diags)


def test_level_has_at_most_one_display_key(tmp_path):
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    day = _named(payload["levels"], "day")
    _named(day["keys"], "date_key")["display"] = True
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-display-key", "error") in _codes(diags)


def test_level_attribute_must_be_a_field(tmp_path):
    doc = _doc()
    zone = _named(doc["datasets"], "zone")
    payload = _payload(zone)
    _named(payload["levels"], "zone")["attributes"].append("zone_colour")
    _set_payload(zone, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-unknown-field", "error") in _codes(diags)


def test_dataset_with_levels_names_its_row_level(tmp_path):
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    del payload["row_level"]
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/row-level-missing", "error") in _codes(diags)


def test_row_level_key_must_include_the_primary_key(tmp_path):
    """A row and a member are the same thing only when the table's key is a level key."""
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    day = _named(payload["levels"], "day")
    day["keys"] = [k for k in day["keys"] if k["name"] != "date_key"]
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/row-level-key", "error") in _codes(diags)


def test_type_2_rows_are_versions(tmp_path):
    doc = _doc()
    zone = _named(doc["datasets"], "zone")
    payload = _payload(zone)
    payload["row_level"]["versioned"] = False
    _set_payload(zone, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/row-level-versioned", "error") in _codes(diags)


def test_versioned_hierarchy_states_its_rollup(tmp_path):
    doc = _doc()
    zone = _named(doc["datasets"], "zone")
    payload = _payload(zone)
    del payload["hierarchies"][0]["scd_rollup"]
    _set_payload(zone, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/hierarchy-scd-rollup", "error") in _codes(diags)


def test_aggregate_content_level_names_its_key_columns(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS8_monthly_service_summary")
    del source["content_levels"][0]["key_columns"]
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-key-columns-missing", "error") in _codes(diags)


def test_key_columns_match_the_key_arity(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS8_monthly_service_summary")
    source["content_levels"][0]["key"] = "year_month"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-key-columns-arity", "error") in _codes(diags)


def test_unknown_level_key_fails(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS8_monthly_service_summary")
    source["content_levels"][2]["key"] = "payment_method_code"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-unknown-key", "error") in _codes(diags)


def test_key_columns_only_on_aggregate_content(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_pickup_borough")
    payload = _payload(metric)
    payload["at_levels"][0]["key_columns"] = ["pickup_borough"]
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-key-columns-misplaced", "error") in _codes(diags)


def test_aggregate_content_level_needs_its_physical_join(tmp_path):
    """An aggregate is joined to a dimension at the level it holds, so the join must exist."""
    doc = _doc()
    model = _payload(doc)
    model["physical_joins"] = [j for j in model["physical_joins"]
                               if j["name"] != "mart_monthly_service_summary_to_dim_date"]
    _set_payload(doc, model)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-level-unjoined", "error") in _codes(diags)


def test_level_tests_are_current():
    """The generated level test is what the model generates now."""
    result = RUNNER.invoke(app, ["generate-tests", "logical-model", "transformation/tests", "--check"])
    assert result.exit_code == 0, result.stdout


def test_level_tests_report_every_declared_key(tmp_path):
    """Each non-primary key and hierarchy step becomes a reported check."""
    from ossie_levels import generate
    files = generate([_doc()])
    sql = "\n".join(files.values())
    assert "date.month: key year_month names several members" in sql
    assert "zone.Geography: zone rolls up to several borough members" in sql
    assert "LTS8_monthly_service_summary: trips_to_payment_method payment_method key is no member" in sql
    assert "severity='warn'" in sql


def test_content_level_unknown_level_fails(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_levels"][0]["level"] = "fortnight"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-unknown-level", "error") in _codes(diags)


def test_content_level_must_start_at_its_dataset(tmp_path):
    doc = _doc()
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    payload["logical_sources"][0]["content_levels"] = [{"via": "trips_to_vendor"}]
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-wrong-dataset", "error") in _codes(diags)


def test_content_filter_unknown_field_fails(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = "pickup_datetime >= DATE '2024-01-01'"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-filter-unknown-field", "error") in _codes(diags)


def test_content_filter_variables_are_not_supported_yet(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = "pickup_date >= :report_start"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-filter-variable", "error") in _codes(diags)


def test_content_filter_literals_are_not_fields(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = "airport_fee_status = 'not charged' AND pickup_date >= DATE '2024-01-01'"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0, diags


def test_content_filter_needs_a_holding_test(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["note"] = "checked by reading the SQL"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-filter-unheld", "error") in _codes(diags)


def test_navigable_must_be_boolean(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["navigable"] = "no"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-navigable", "error") in _codes(diags)


def test_metric_bad_aggregation_fails(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "trip_count")
    _set_payload(metric, {"vibedata_version": "1.2", "aggregation": "AVG"})
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-aggregation", "error") in _codes(diags)


def test_metric_unknown_key_fails(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "trip_count")
    _set_payload(metric, {"vibedata_version": "1.2", "dimensionality": ["zone"]})
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/unknown-key", "error") in _codes(diags)


def test_metric_version_counts_toward_consistency(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "trip_count")
    _set_payload(metric, {"vibedata_version": "1.1", "aggregation": "SUM"})
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/version-mismatch", "error") in _codes(diags)


def test_level_based_metric_needs_a_level(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_pickup_borough")
    payload = _payload(metric)
    payload["at_levels"] = [{"via": "trips_to_pickup_zone"}]
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-needs-level", "error") in _codes(diags)


def test_time_series_expression_must_match_its_base(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_prior_month")
    metric["expression"]["dialects"][0]["expression"] = "SUM(trips.total_amount)"
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/time-series-expression", "error") in _codes(diags)


def test_time_series_needs_a_time_hierarchy(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_prior_month")
    payload = _payload(metric)
    payload["time_series"].update(
        {"via": "trips_to_pickup_zone", "level": "borough"})
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/time-series-not-time", "error") in _codes(diags)


def test_ago_needs_an_offset(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_prior_month")
    payload = _payload(metric)
    del payload["time_series"]["offset"]
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-time-series", "error") in _codes(diags)


FLEET = Path("logical-model/nyc_taxi_fleet.ossie.yaml")


def test_derived_metric_bound_to_a_column_fails(tmp_path):
    """A post-aggregation ratio read from an aggregate column re-sums ratios (ADR 0016)."""
    doc = yaml.safe_load(FLEET.read_text())
    shift = _named(doc["datasets"], "shift")
    payload = _payload(shift)
    _named(payload["logical_sources"], "LTS2_driver_day")["column_map"]["occupancy_rate"] = "occupancy_rate"
    _set_payload(shift, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/computed-metric-mapped", "error") in _codes(diags)


def test_derived_metric_unknown_input_fails(tmp_path):
    doc = yaml.safe_load(FLEET.read_text())
    metric = _named(doc["metrics"], "occupancy_rate")
    _set_payload(metric, {"vibedata_version": "1.2",
                          "derived_expression": "on_trip_hours / NULLIF(paid_hours, 0)"})
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/derived-unknown-metric", "error") in _codes(diags)


def test_suppliers_follow_derived_inputs(tmp_path):
    """A derived metric is supplied through its inputs; drop an input and it goes unsupplied."""
    model = tmp_path / "model"
    model.mkdir()
    doc = yaml.safe_load(FLEET.read_text())
    shift = _named(doc["datasets"], "shift")
    payload = _payload(shift)
    for source in payload["logical_sources"]:
        source["column_map"].pop("on_trip_hours", None)
    _set_payload(shift, payload)
    (model / "m.ossie.yaml").write_text(yaml.safe_dump(doc))
    result = RUNNER.invoke(app, ["suppliers", str(model)])
    assert result.exit_code == 1
    assert "on_trip_hours" in result.stdout
    assert "occupancy_rate" in result.stdout


def test_crossdoc_diverged_metric_payload_fails(tmp_path):
    model = tmp_path / "model"
    model.mkdir()
    doc = _doc()
    (model / "a.ossie.yaml").write_text(yaml.safe_dump(doc))
    twin = _doc()
    twin["name"] = "twin"
    _set_payload(_named(twin["metrics"], "trip_count"),
                 {"vibedata_version": "1.2", "aggregation": "MAX"})
    (model / "b.ossie.yaml").write_text(yaml.safe_dump(twin))
    code, diags = _run("validate", str(model))
    assert code == 1
    assert any(d["code"] == "crossdoc/diverged" and "metric 'trip_count'" in d["message"]
               for d in diags)


def _rule(doc, name):
    metric = _named(doc["metrics"], name)
    return metric, _payload(metric)


def test_dimension_rule_expression_must_match_its_metric(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "avg_daily_billable_revenue")
    metric["expression"]["dialects"][0]["expression"] = "SUM(trips.total_amount)"
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/based-on-expression", "error") in _codes(diags)


def test_last_needs_a_time_level(tmp_path):
    """LAST is a time balance: it needs one chronological level to order members by."""
    doc = yaml.safe_load(FLEET.read_text())
    metric, payload = _rule(doc, "closing_active_driver_count")
    payload["based_on_dimensions"]["across"] = [{"via": "shift_to_driver"}]
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/based-on-order-not-time", "error") in _codes(diags)


def test_dimension_rule_must_be_known(tmp_path):
    doc = _doc()
    metric, payload = _rule(doc, "avg_daily_billable_revenue")
    payload["based_on_dimensions"]["rule"] = "MODE"
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-based-on", "error") in _codes(diags)


def test_metric_declares_one_computation(tmp_path):
    doc = _doc()
    metric, payload = _rule(doc, "avg_daily_billable_revenue")
    payload["time_series"] = {"function": "TODATE", "of": "billable_revenue",
                              "via": "trips_to_date", "level": "month"}
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/metric-semantics-conflict", "error") in _codes(diags)


def test_dimension_rule_metric_bound_to_a_column_fails(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS7_daily_zone_revenue")
    source["column_map"]["avg_daily_billable_revenue"] = "total_revenue"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/computed-metric-mapped", "error") in _codes(diags)


def test_metric_cycle_fails(tmp_path):
    doc = _doc()
    metric, payload = _rule(doc, "billable_average_fare")
    payload["derived_expression"] = "mean_pickup_zone_average_fare * 1.0"
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/metric-cycle", "error") in _codes(diags)


def test_suppliers_follow_dimension_rule_inputs(tmp_path):
    """A dimension-rule metric is supplied through the metric it aggregates."""
    model = tmp_path / "model"
    model.mkdir()
    doc = yaml.safe_load(FLEET.read_text())
    shift = _named(doc["datasets"], "shift")
    payload = _payload(shift)
    for source in payload["logical_sources"]:
        source["column_map"].pop("active_driver_count", None)
    _set_payload(shift, payload)
    (model / "m.ossie.yaml").write_text(yaml.safe_dump(doc))
    result = RUNNER.invoke(app, ["suppliers", str(model)])
    assert result.exit_code == 1
    assert "avg_daily_active_drivers" in result.stdout
    assert "closing_active_driver_count" in result.stdout


def test_content_filter_must_parse(tmp_path):
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = "pickup_date >= AND"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-filter-unparsable", "error") in _codes(diags)


def test_aggregate_binding_needs_a_holding_test(tmp_path):
    """An aggregate that binds a metric claims the detail's answer; a test must hold it."""
    doc = yaml.safe_load(FLEET.read_text())
    shift = _named(doc["datasets"], "shift")
    payload = _payload(shift)
    source = _named(payload["logical_sources"], "LTS3_driver_month")
    del source["content_filter"]
    source["note"] = "checked by reading the SQL"
    _set_payload(shift, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/aggregate-binding-unheld", "error") in _codes(diags)


def _with_join_expression(text, rel="trips_to_pickup_zone"):
    doc = _doc()
    relationship = _named(doc["relationships"], rel)
    payload = _payload(relationship)
    payload["join_expression"] = text
    _set_payload(relationship, payload)
    return doc


def test_join_expression_in_ossie_field_grammar_passes(tmp_path):
    doc = _with_join_expression(
        "trips.pickup_zone_key = zone.zone_key AND trips.pickup_date >= zone.valid_from_date")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0, diags


def test_join_expression_columns_are_dataset_qualified(tmp_path):
    doc = _with_join_expression("pickup_zone_key = zone_key")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/join-expression-unqualified", "error") in _codes(diags)


def test_join_expression_reads_declared_fields(tmp_path):
    """The audit that started this: a predicate on a column neither side declares."""
    doc = _with_join_expression("trips.vendor_id = vendor.vendor_natural_key", "trips_to_vendor")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/join-expression-unknown-field", "error") in _codes(diags)


def test_join_expression_must_parse(tmp_path):
    doc = _with_join_expression("trips.pickup_zone_key = ; drop table x")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/join-expression-unparsable", "error") in _codes(diags)


def test_join_expression_reads_no_variables(tmp_path):
    doc = _with_join_expression("trips.pickup_date >= :start AND trips.pickup_zone_key = zone.zone_key")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/join-expression-variable", "error") in _codes(diags)


def test_unquoted_identifiers_are_case_insensitive(tmp_path):
    """Ossie's expression language: an unquoted identifier matches any case."""
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = source["content_filter"].replace("pickup_zone_key", "PICKUP_ZONE_KEY")
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 0, diags


def test_expressions_are_checked_by_ossie_itself(tmp_path):
    """Ossie's own check rejects a statement list hidden in an expression."""
    doc = _doc()
    trips, payload, source = _trips_source(doc, "LTS2_zone_day_agg")
    source["content_filter"] = "pickup_zone_key IS NOT NULL; DROP TABLE trips"
    _set_payload(trips, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert any(d["code"] == "vibedata/content-filter-unparsable" and "statements" in d["message"]
               for d in diags), diags


def _catalog_for(doc):
    """A dbt catalog holding exactly the columns the document maps or reads."""
    import ossie_columns
    import ossie_sql
    nodes = {}
    def add(source, column):
        schema, name = source.split(".")
        node = nodes.setdefault(source, {"metadata": {"schema": schema, "name": name}, "columns": {}})
        node["columns"][column] = {"name": column}
    tables = {t["name"]: t for t in _payload(doc)["physical_tables"]}
    for table in tables.values():
        nodes.setdefault(table["source"], {"metadata": dict(zip(("schema", "name"), table["source"].split("."))), "columns": {}})
    for dataset in doc["datasets"]:
        for field in dataset.get("fields") or []:
            for name in ossie_sql.names(field["expression"]["dialects"][0]["expression"])[0]:
                add(dataset["source"], name)
        for src in ossie_columns._payload(dataset).get("logical_sources") or []:
            for physical in (src.get("column_map") or {}).values():
                add(tables[src["physical_table"]]["source"], physical)
            for ref in src.get("content_levels") or []:
                for column in ref.get("key_columns") or []:
                    add(tables[src["physical_table"]]["source"], column)
    return {"nodes": nodes, "sources": {}}


def test_columns_pass_against_a_complete_catalog(tmp_path):
    catalog = tmp_path / "catalog.json"
    catalog.write_text(json.dumps(_catalog_for(_doc())))
    result = RUNNER.invoke(app, ["columns", str(CANONICAL), str(catalog)])
    assert result.exit_code == 0, result.stdout


def test_columns_catch_a_map_onto_a_missing_column(tmp_path):
    doc = _doc()
    catalog = tmp_path / "catalog.json"
    catalog.write_text(json.dumps(_catalog_for(doc)))
    trips, payload, source = _trips_source(doc, "LTS7_daily_zone_revenue")
    source["column_map"]["billable_revenue"] = "total_revenu"
    _set_payload(trips, payload)
    result = RUNNER.invoke(app, ["columns", str(_write(tmp_path, doc)), str(catalog)])
    assert result.exit_code == 1
    assert "columns/map-unknown-column" in result.stdout and "total_revenu" in result.stdout


def test_columns_catch_a_field_reading_a_missing_column(tmp_path):
    doc = _doc()
    catalog = tmp_path / "catalog.json"
    catalog.write_text(json.dumps(_catalog_for(doc)))
    field = _named(_named(doc["datasets"], "trips")["fields"], "fare_residual")
    field["expression"]["dialects"][0]["expression"] = "fare_residual_amount"
    result = RUNNER.invoke(app, ["columns", str(_write(tmp_path, doc)), str(catalog)])
    assert result.exit_code == 1
    assert "columns/field-unknown-column" in result.stdout


def test_columns_need_a_catalog(tmp_path):
    result = RUNNER.invoke(app, ["columns", str(CANONICAL), str(tmp_path / "missing.json")])
    assert result.exit_code == 1
    assert "columns/no-catalog" in result.stdout


STAR = SKILL_SCRIPTS.parent / "examples" / "star.ossie.yaml"


def _metric_payload_set(doc, name, **changes):
    metric = _named(doc["metrics"], name)
    payload = _payload(metric)
    payload.update(changes)
    _set_payload(metric, payload)
    return metric


def test_metric_filter_must_be_qualified(tmp_path):
    doc = _doc()
    _metric_payload_set(doc, "billable_revenue", filter="is_billable")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/filter-unqualified", "error") in _codes(diags)


def test_metric_filter_unknown_field_fails(tmp_path):
    doc = _doc()
    _metric_payload_set(doc, "billable_revenue", filter="trips.is_refund")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/filter-unknown-field", "error") in _codes(diags)


def test_metric_filter_must_be_read_by_the_expression(tmp_path):
    """A filter the expression does not apply would declare a population nobody computes."""
    doc = _doc()
    _metric_payload_set(doc, "billable_revenue", filter="trips.is_fleet_attributed")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/filter-not-in-expression", "error") in _codes(diags)


def test_metric_filter_not_on_computed_metric(tmp_path):
    doc = _doc()
    _metric_payload_set(doc, "billable_revenue_prior_month", filter="trips.is_billable")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/filter-on-computed-metric", "error") in _codes(diags)


def test_unrelated_dimensions_value_checked(tmp_path):
    doc = _doc()
    _metric_payload_set(doc, "trip_count", unrelated_dimensions="blank")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-unrelated", "error") in _codes(diags)


def test_rolling_needs_periods(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_rolling_28_days")
    payload = _payload(metric)
    del payload["time_series"]["periods"]
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-time-series", "error") in _codes(diags)


def test_periods_belongs_to_rolling_only(tmp_path):
    doc = _doc()
    metric = _named(doc["metrics"], "billable_revenue_prior_month")
    payload = _payload(metric)
    payload["time_series"]["periods"] = 3
    _set_payload(metric, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/bad-time-series", "error") in _codes(diags)


def _bridge(doc, **changes):
    rel = _named(doc["relationships"], "zone_poi_to_zone")
    payload = _payload(rel)
    payload.update(changes)
    _set_payload(rel, payload)
    return rel


def test_to_level_columns_must_be_the_level_key(tmp_path):
    doc = _doc()
    rel = _bridge(doc)
    rel["to_columns"] = ["zone_key"]
    rel["from_columns"] = ["poi_id"]
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/to-level-key-mismatch", "error") in _codes(diags)


def test_to_level_unknown_level_fails(tmp_path):
    doc = _doc()
    _bridge(doc, to_level="street")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-unknown-level", "error") in _codes(diags)


def test_bridge_weight_must_be_a_numeric_field(tmp_path):
    doc = _doc()
    _bridge(doc, weight="poi_name")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/weight-not-numeric", "error") in _codes(diags)
    _bridge(doc, weight="nope")
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert ("vibedata/weight-unknown-field", "error") in _codes(diags)


def _month_table(doc):
    date = _named(doc["datasets"], "date")
    payload = _payload(date)
    return date, payload, _named(payload["logical_sources"], "LTS2_month_table")


def test_month_table_cannot_supply_a_day_field(tmp_path):
    """A dimension source held at month supplies month and above, never a day."""
    doc = yaml.safe_load(STAR.read_text())
    date, payload, source = _month_table(doc)
    source["column_map"]["calendar_date"] = "first_day"
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/own-level-finer-field", "error") in _codes(diags)


def test_own_level_needs_key_columns(tmp_path):
    doc = yaml.safe_load(STAR.read_text())
    date, payload, source = _month_table(doc)
    del source["content_levels"][0]["key_columns"]
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/level-ref-key-columns-missing", "error") in _codes(diags)


def test_own_level_only_on_a_coarser_source(tmp_path):
    doc = yaml.safe_load(STAR.read_text())
    date, payload, source = _month_table(doc)
    source["priority_group"] = 1
    _set_payload(date, payload)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/own-level-on-detail", "error") in _codes(diags)


def test_monthly_aggregate_must_join_a_table_at_its_level(tmp_path):
    """The monthly aggregate is honest only while it joins the month table (or the day one)."""
    doc = yaml.safe_load(STAR.read_text())
    model = _payload(doc)
    model["physical_joins"] = [j for j in model["physical_joins"]
                               if j["name"] != "agg_order_monthly_to_dim_month"]
    _set_payload(doc, model)
    code, diags = _run("validate", str(_write(tmp_path, doc)))
    assert code == 1
    assert ("vibedata/content-level-unjoined", "error") in _codes(diags)


def _dimensionality(path):
    result = RUNNER.invoke(app, ["dimensionality", str(path)])
    assert result.exit_code == 0, result.output
    return json.loads(result.stdout)


def test_dimensionality_errors_where_a_fact_has_no_path():
    fleet = _dimensionality(FLEET)["nyc_taxi_fleet"]
    assert "zone" not in fleet["online_hours"]["dimensions"]
    assert fleet["online_hours"]["unrelated_dimensions"] == "error"
    assert "zone" in fleet["on_trip_interval_hours"]["dimensions"]


def test_dimensionality_total_metric_answers_every_dimension():
    fleet = _dimensionality(FLEET)["nyc_taxi_fleet"]
    total = fleet["fleet_on_trip_hours"]
    assert total["unrelated_dimensions"] == "total"
    assert {"zone", "daypart"} <= set(total["dimensions"])
    assert "status_interval" not in total["dimensions"]  # another fact, not a dimension
    share = fleet["zone_share_of_fleet_on_trip_hours"]
    assert {"zone", "daypart", "driver"} <= set(share["dimensions"])
    assert "garage" not in share["dimensions"]  # the interval fact cannot reach it


def test_dimensionality_follows_a_weighted_bridge_only(tmp_path):
    trips = _dimensionality(CANONICAL)["nyc_taxi_trips"]
    assert "zone_poi" in trips["billable_revenue"]["dimensions"]
    doc = _doc()
    rel = _named(doc["relationships"], "zone_poi_to_zone")
    payload = _payload(rel)
    del payload["weight"]
    _set_payload(rel, payload)
    unweighted = _dimensionality(_write(tmp_path, doc))["nyc_taxi_trips"]
    assert "zone_poi" not in unweighted["billable_revenue"]["dimensions"]


VENDOR = SKILL_SCRIPTS / "ossie_vendor"


def test_vendor_mirrors_the_upstream_tree():
    """The vendored registry resolves $refs inside ossie_vendor/, so the tree mirrors upstream."""
    for rel in ("validation/validate.py", "core-spec/ossie-schema.json",
                "ontology/ontology.json", "ontology/mapping.json"):
        assert (VENDOR / rel).is_file(), rel


def test_ontology_schema_resolves_offline():
    """The ontology schema $refs the core schema by URL; it must resolve with no network."""
    import ossie
    schema, diag = ossie._load_schema("ontology")
    assert diag is None, diag
    doc = {"version": "0.2.0.dev0", "name": "X", "ontology": [
        {"concept": "A", "type": "EntityType"}]}
    assert ossie._vendor.validate_document(doc, schema) == []


ONTOLOGY = {
    "version": "0.2.0.dev0", "name": "taxi",
    "ontology": [
        {"concept": "Trip", "type": "EntityType", "identify_by": ["trip_id"],
         "relationships": [
             {"name": "trip_id", "verbalizes": ["a trip's identifier"],
              "multiplicity": "OneToOne", "roles": [{"concept": "TripKey"}]},
             {"name": "pickup_zone", "verbalizes": ["the zone a trip starts in"],
              "multiplicity": "ManyToOne", "roles": [{"concept": "Zone"}]}]},
        {"concept": "Zone", "type": "EntityType", "identify_by": ["zone_id"],
         "relationships": [
             {"name": "zone_id", "verbalizes": ["a zone's identifier"],
              "multiplicity": "OneToOne", "roles": [{"concept": "ZoneId"}]}]},
        {"concept": "TripKey", "type": "ValueType", "extends": ["String"]},
        {"concept": "ZoneId", "type": "ValueType", "extends": ["Integer"]},
    ],
}

MODEL = {"version": "0.2.0.dev0", "name": "nyc_taxi_analytics", "datasets": [
    {"name": "trips", "fields": [{"name": "trip_key"}, {"name": "pickup_zone_key"}]}]}

MAPPING = {
    "version": "0.2.0.dev0", "name": "taxi_analytics",
    "ontology_ref": {"name": "taxi"},
    "semantic_model_ref": {"name": "nyc_taxi_analytics"},
    "concept_mappings": [
        {"concept": "Trip", "object_mappings": [{"expression": "trips.trip_key"}]},
        {"concept": "Zone", "link_mappings": [
            {"relationship": "pickup_zone",
             "object_mapping": {"expression": "trips.pickup_zone_key"}}]},
    ],
}


def _write_doc(directory, filename, doc):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / filename).write_text(yaml.safe_dump(doc))


def _refs(tmp_path, mapping=None, model=None, ontology=None):
    ontology_dir = tmp_path / "ontology"
    model_dir = tmp_path / "logical-model"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ontology or ONTOLOGY)
    _write_doc(ontology_dir, "taxi.mapping.yaml", mapping or MAPPING)
    _write_doc(model_dir, "nyc_taxi_analytics.ossie.yaml", model or MODEL)
    return RUNNER.invoke(app, ["refs", str(ontology_dir), str(model_dir)])


def test_validate_detects_ontology_and_mapping_kinds(tmp_path):
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ONTOLOGY)
    _write_doc(ontology_dir, "taxi.mapping.yaml", MAPPING)
    code, diags = _run("validate", str(ontology_dir))
    assert code == 0, diags
    assert not [d for d in diags if d["severity"] == "error"]


def test_refs_resolves_a_valid_mapping(tmp_path):
    result = _refs(tmp_path)
    assert result.exit_code == 0, result.stdout


def test_refs_flags_unknown_semantic_model(tmp_path):
    mapping = dict(MAPPING, semantic_model_ref={"name": "other"})
    result = _refs(tmp_path, mapping=mapping)
    assert result.exit_code == 1
    assert "mapping/unresolved-ref" in result.stdout


def test_refs_flags_a_field_the_model_does_not_expose(tmp_path):
    mapping = dict(MAPPING, concept_mappings=[
        {"concept": "Trip", "object_mappings": [{"expression": "trips.no_such_field"}]}])
    result = _refs(tmp_path, mapping=mapping)
    assert result.exit_code == 1
    assert "mapping/unknown-field" in result.stdout


def test_refs_reports_a_model_with_no_mapping(tmp_path):
    result = _refs(tmp_path, mapping=dict(
        MAPPING, semantic_model_ref={"name": "nyc_taxi_analytics"}))
    other = tmp_path / "logical-model" / "other.ossie.yaml"
    other.write_text(yaml.safe_dump(dict(MODEL, name="other_model")))
    result = RUNNER.invoke(app, ["refs", str(tmp_path / "ontology"),
                                 str(tmp_path / "logical-model")])
    assert result.exit_code == 0, result.stdout
    assert "mapping/none" in result.stdout


def test_validate_flags_declaration_only_fields_as_warnings(tmp_path):
    ontology = yaml.safe_load(yaml.safe_dump(ONTOLOGY))
    ontology["ontology"][0]["requires"] = ["trip_key is not null"]
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ontology)
    code, diags = _run("validate", str(ontology_dir))
    assert code == 0, diags
    assert ("declaration-only", "warning") in _codes(diags)


def test_validate_flags_an_entity_without_identity(tmp_path):
    ontology = yaml.safe_load(yaml.safe_dump(ONTOLOGY))
    ontology["ontology"][0].pop("identify_by")
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ontology)
    code, diags = _run("validate", str(ontology_dir))
    assert code == 1
    assert ("ontology/no-identity", "error") in _codes(diags)


def test_refs_fails_on_a_mistyped_directory(tmp_path):
    """A gate on a missing path must fail, not report zero findings."""
    result = RUNNER.invoke(app, ["refs", str(tmp_path / "nope"), str(tmp_path / "nope")])
    assert result.exit_code == 1
    assert "cli/no-files" in result.stdout


def test_refs_reports_a_document_that_is_not_a_mapping(tmp_path):
    """A list is valid YAML and not a document; it must not crash the checker."""
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ONTOLOGY)
    (ontology_dir / "bad.mapping.yaml").write_text("- a\n- list\n")
    _write_doc(tmp_path / "logical-model", "nyc_taxi_analytics.ossie.yaml", MODEL)
    result = RUNNER.invoke(app, ["refs", str(ontology_dir), str(tmp_path / "logical-model")])
    assert result.exit_code == 1
    assert "cli/not-a-document" in result.stdout


def test_ontology_flags_an_iri_on_a_concept(tmp_path):
    """An iri names a vocabulary nothing resolves, so it is refused on a concept."""
    ontology = yaml.safe_load(yaml.safe_dump(ONTOLOGY))
    ontology["ontology"][0]["iri"] = "https://example.org/Trip"
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ontology)
    code, diags = _run("validate", str(ontology_dir))
    assert code == 0, diags
    assert ("declaration-only", "warning") in _codes(diags)


def test_notes_says_when_a_directory_is_missing(tmp_path):
    """A clean notes run over a missing directory must not read as proof."""
    model = tmp_path / "logical-model"
    _write_doc(model, "m.ossie.yaml", MODEL)
    result = RUNNER.invoke(app, ["notes", str(model), str(tmp_path / "no-tests"),
                                 str(tmp_path / "no-adr")])
    assert result.exit_code == 0, result.stdout
    assert "notes/no-directory" in result.stdout


def test_glossary_reports_both_directions_without_judging(tmp_path):
    """Both lists are reported; only an entity type with no term fails."""
    ontology_dir = tmp_path / "ontology"
    _write_doc(ontology_dir, "taxi.ontology.yaml", ONTOLOGY)
    context = tmp_path / "CONTEXT.md"
    context.write_text("# Context\n\n**Trip**:\nA journey.\n\n**Billable trip**:\nA rule.\n")
    result = RUNNER.invoke(app, ["glossary", str(ontology_dir), str(context)])
    assert result.exit_code == 1, result.stdout  # an entity type with no term fails
    out = json.loads(result.stdout)
    assert out["entity_types_without_term"] == ["Zone"]
    assert out["terms_without_concept"] == ["Billable trip"]
    assert out["value_types_without_term"]  # value types need no term


def test_glossary_fails_only_on_a_mistyped_path(tmp_path):
    context = tmp_path / "CONTEXT.md"
    context.write_text("**Trip**:\nA journey.\n")
    result = RUNNER.invoke(app, ["glossary", str(tmp_path / "nope"), str(context)])
    assert result.exit_code == 1
    assert "cli/no-files" in result.stdout
