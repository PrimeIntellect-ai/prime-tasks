#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_instrument

cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import os

MARKER = os.environ.get("PIPELINE_MARKER")

def mark(value):
    if MARKER:
        with open(MARKER, "a", encoding="utf-8") as f:
            f.write(value + "\n")

try:
    import rdflib
    _original_query = rdflib.Graph.query

    def _recording_query(self, *args, **kwargs):
        mark("SPARQL_QUERY")
        return _original_query(self, *args, **kwargs)

    rdflib.Graph.query = _recording_query
except Exception:
    pass

try:
    import jsonschema

    _original_validate = jsonschema.validate

    def _recording_validate(instance, *args, **kwargs):
        mark("JSONSCHEMA:" + type(instance).__name__)
        return _original_validate(instance, *args, **kwargs)

    jsonschema.validate = _recording_validate

    _seen = set()
    for _name in dir(jsonschema):
        if not (_name.startswith("Draft") and _name.endswith("Validator")):
            continue
        _cls = getattr(jsonschema, _name)
        if not isinstance(_cls, type) or id(_cls) in _seen:
            continue
        _seen.add(id(_cls))
        for _method_name in ("validate", "is_valid", "iter_errors"):
            try:
                _original = getattr(_cls, _method_name)

                def _make_wrapper(original):
                    def wrapper(self, *args, **kwargs):
                        instance = args[0] if args else kwargs.get("instance")
                        mark("JSONSCHEMA:" + type(instance).__name__)
                        return original(self, *args, **kwargs)
                    return wrapper

                setattr(_cls, _method_name, _make_wrapper(_original))
            except Exception:
                pass
except Exception:
    pass
PY_EOF

cat << 'PY_EOF' > /tmp/test_pipeline.py
import json
import os
import secrets
import stat
import subprocess
from pathlib import Path

import jsonschema

HOME = Path("/home/user")
SCRIPT = HOME / "process_graph.py"
RAW = HOME / "raw_papers.json"
INPUT_SCHEMA = HOME / "input_schema.json"
OUTPUT_SCHEMA = HOME / "output_schema.json"
OUTPUT = HOME / "top_authors.json"
MARKER = Path("/tmp/pipeline_marker.log")

CANONICAL_RAW = [
    {"id": "p1", "authors": ["Alice_Smith"], "venue": "Nature", "cites": []},
    {"id": "p2", "authors": ["Bob_Jones"], "venue": "Science", "cites": ["p1"]},
    {"id": "p3", "authors": ["Charlie_Brown"], "venue": "Science", "cites": ["p1"]},
    {"id": "p4", "authors": ["Dave_White"], "venue": "Nature", "cites": ["p1"]},
    {"id": "p6", "authors": ["Eve_Davis"], "venue": "Journal of AI", "cites": []},
    {"id": "p5", "authors": ["Frank_Miller"], "venue": "Science", "cites": ["p6"]},
    {"id": "p7", "authors": ["Grace_Hopper"], "venue": "Science", "cites": ["p6"]},
    {"id": "p8", "authors": ["Heidi_Klum"], "venue": "Science", "cites": ["p6"]},
    {"id": "p10", "authors": ["Ivan_Drago"], "venue": "ArXiv", "cites": []},
    {"id": "p11", "authors": ["Judy_Garland"], "venue": "Science", "cites": ["p10", "p1"]},
    {"id": "p99", "venue": "Science", "cites": ["p1"]},
]

CANONICAL_INPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "authors": {"type": "array", "items": {"type": "string"}, "minItems": 1},
        "venue": {"type": "string"},
        "cites": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["id", "authors", "venue", "cites"],
}

CANONICAL_OUTPUT_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "author": {"type": "string"},
            "science_citations": {"type": "integer"},
        },
        "required": ["author", "science_citations"],
    },
    "maxItems": 3,
}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def run_pipeline(raw, input_schema, output_schema):
    write_json(RAW, raw)
    write_json(INPUT_SCHEMA, input_schema)
    write_json(OUTPUT_SCHEMA, output_schema)
    if OUTPUT.exists():
        OUTPUT.unlink()
    if MARKER.exists():
        MARKER.unlink()

    env = os.environ.copy()
    env["PIPELINE_MARKER"] = str(MARKER)
    env["PYTHONPATH"] = "/tmp/verifier_instrument" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd=str(HOME),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_graph.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.is_file(), f"Output file {OUTPUT} does not exist. The pipeline must generate this file."
    try:
        data = json.loads(OUTPUT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{OUTPUT} is not a valid JSON file: {exc}")

    events = MARKER.read_text(encoding="utf-8").splitlines() if MARKER.exists() else []
    assert "SPARQL_QUERY" in events, "The pipeline did not execute an rdflib Graph.query SPARQL query."
    assert "JSONSCHEMA:dict" in events, "The pipeline did not use jsonschema to validate paper records."
    assert "JSONSCHEMA:list" in events, "The pipeline did not use jsonschema to validate the output array."
    return data


def derive_expected(raw, schema):
    valid = []
    for record in raw:
        try:
            jsonschema.validate(record, schema)
            valid.append(record)
        except jsonschema.ValidationError:
            pass

    authors_by_id = {record["id"]: record["authors"] for record in valid}
    counts = {}
    for source in valid:
        if source["venue"] != "Science":
            continue
        for target_id in source["cites"]:
            for author in authors_by_id.get(target_id, []):
                rendered = author.replace(" ", "_")
                counts[rendered] = counts.get(rendered, 0) + 1

    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:3]
    return [{"author": author, "science_citations": count} for author, count in ranked]


def assert_original_output(data):
    assert isinstance(data, list), f"The output in {OUTPUT} must be a JSON array."
    assert len(data) == 3, f"The output must contain exactly 3 items, but found {len(data)}."

    expected = [
        {"author": "Alice_Smith", "science_citations": 3},
        {"author": "Eve_Davis", "science_citations": 3},
        {"author": "Ivan_Drago", "science_citations": 1},
    ]

    for i, (actual_item, expected_item) in enumerate(zip(data, expected)):
        assert isinstance(actual_item, dict), f"Item at index {i} is not a JSON object."
        assert "author" in actual_item, f"Item at index {i} is missing the 'author' key."
        assert "science_citations" in actual_item, f"Item at index {i} is missing the 'science_citations' key."
        assert actual_item["author"] == expected_item["author"], (
            f"At rank {i+1}, expected author '{expected_item['author']}' but got '{actual_item['author']}'."
        )
        assert actual_item["science_citations"] == expected_item["science_citations"], (
            f"At rank {i+1}, expected science_citations {expected_item['science_citations']} "
            f"for '{actual_item['author']}' but got {actual_item['science_citations']}."
        )


def make_dynamic_case():
    token = secrets.token_hex(5)
    target_specs = [
        (f"target_a_{token}", f"Alpha {token}", 4),
        (f"target_z_{token}", f"Zulu {token}", 4),
        (f"target_m_{token}", f"Middle {token}", 2),
        (f"target_l_{token}", f"Low {token}", 1),
    ]
    records = []
    for paper_id, author, _ in target_specs:
        records.append({"id": paper_id, "authors": [author], "venue": "Nature", "cites": []})

    source_number = 0
    for target_id, _, count in target_specs:
        for _ in range(count):
            source_number += 1
            records.append({
                "id": f"science_source_{source_number}_{token}",
                "authors": [f"Source {source_number} {token}"],
                "venue": "Science",
                "cites": [target_id],
            })

    # These records distinguish Science-only counting and schema filtering.
    records.append({
        "id": f"nature_noise_{token}",
        "authors": [f"Noise {token}"],
        "venue": "Nature",
        "cites": [target_specs[3][0], target_specs[3][0]],
    })
    records.append({
        "id": f"invalid_missing_authors_{token}",
        "venue": "Science",
        "cites": [target_specs[2][0]],
    })
    records.append({
        "id": f"invalid_author_type_{token}",
        "authors": [17],
        "venue": "Science",
        "cites": [target_specs[3][0]],
    })
    records.append({
        "id": f"invalid_extra_property_{token}",
        "authors": [f"Invalid {token}"],
        "venue": "Science",
        "cites": [target_specs[3][0]],
        "unexpected": True,
    })
    secrets.SystemRandom().shuffle(records)

    input_schema = {
        "type": "object",
        "properties": {
            "id": {"type": "string", "minLength": 1},
            "authors": {"type": "array", "items": {"type": "string"}, "minItems": 1},
            "venue": {"type": "string"},
            "cites": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["id", "authors", "venue", "cites"],
        "additionalProperties": False,
    }
    output_schema = {
        "type": "array",
        "minItems": 3,
        "maxItems": 3,
        "items": {
            "type": "object",
            "properties": {
                "author": {"type": "string"},
                "science_citations": {"type": "integer", "minimum": 0},
            },
            "required": ["author", "science_citations"],
            "additionalProperties": False,
        },
    }
    return records, input_schema, output_schema


def main():
    assert SCRIPT.exists(), f"Required processing script {SCRIPT} does not exist."
    assert not SCRIPT.is_symlink(), f"{SCRIPT} must be a regular submitted Python file, not a symlink."
    mode = SCRIPT.stat().st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
    source = SCRIPT.read_text(encoding="utf-8")
    assert source.strip(), f"{SCRIPT} is empty."
    compile(source, str(SCRIPT), "exec")

    original = run_pipeline(CANONICAL_RAW, CANONICAL_INPUT_SCHEMA, CANONICAL_OUTPUT_SCHEMA)
    assert_original_output(original)

    dynamic_raw, dynamic_input_schema, dynamic_output_schema = make_dynamic_case()
    expected = derive_expected(dynamic_raw, dynamic_input_schema)
    actual = run_pipeline(dynamic_raw, dynamic_input_schema, dynamic_output_schema)
    jsonschema.validate(actual, dynamic_output_schema)
    assert actual == expected, f"Dynamic pipeline result was {actual!r}; expected {expected!r}."


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
