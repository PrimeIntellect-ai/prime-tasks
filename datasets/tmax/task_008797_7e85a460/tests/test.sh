#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid

import jsonschema
import pytest

HOME = "/home/user"
METADATA = f"{HOME}/metadata.jsonl"
TOP = f"{HOME}/top_datasets.json"
FINAL = f"{HOME}/final_pairs.json"
PIPELINE = f"{HOME}/run_pipeline.sh"
GRAPH = f"{HOME}/graph_query.py"
SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "source_dataset": {"type": "string"},
            "target_dataset": {"type": "string"},
        },
        "required": ["source_dataset", "target_dataset"],
    },
}
ORIGINAL_RUN = {}


def run_pipeline():
    return subprocess.run(
        [PIPELINE],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def has_valid_line(stdout):
    return any(line.strip() == "VALID" for line in stdout.splitlines())


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def expected_for(records):
    impact = {}
    for paper in records:
        for dataset in paper["datasets"]:
            impact[dataset] = impact.get(dataset, 0) + paper["citation_count"]

    top = [d for d, _ in sorted(impact.items(), key=lambda item: (-item[1], item[0]))[:2]]
    pairs = set()
    for source in top:
        for used_by in records:
            if source not in used_by["datasets"]:
                continue
            for citing in records:
                if used_by["paper_id"] not in citing["citations"]:
                    continue
                for target in citing["datasets"]:
                    if target != source:
                        pairs.add((source, target))
    return top, pairs


@pytest.fixture(scope="module", autouse=True)
def preserve_metadata_and_run_original():
    with open(METADATA, "rb") as f:
        original_metadata = f.read()
    try:
        result = run_pipeline()
        ORIGINAL_RUN["result"] = result
        assert result.returncode == 0, (
            f"run_pipeline.sh failed on the supplied metadata. stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert has_valid_line(result.stdout), "run_pipeline.sh did not print VALID on success"
        yield
    finally:
        with open(METADATA, "wb") as f:
            f.write(original_metadata)


def test_top_datasets():
    """Test that the top_datasets.json contains the correct top 2 datasets."""
    path = "/home/user/top_datasets.json"
    assert os.path.exists(path), f"File {path} does not exist. Did you run Phase 1?"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} is not valid JSON."

    assert isinstance(data, list), f"{path} must contain a JSON array."
    assert set(data) == {"d2", "d4"}, f"Expected top datasets to be {{'d2', 'd4'}}, got {set(data)}"


def test_final_pairs():
    """Test that final_pairs.json contains the correct knowledge graph pattern matches."""
    path = "/home/user/final_pairs.json"
    assert os.path.exists(path), f"File {path} does not exist. Did you run the full pipeline?"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} is not valid JSON."

    assert isinstance(data, list), f"{path} must contain a JSON array."

    expected_pairs = [
        {"source_dataset": "d2", "target_dataset": "d4"},
        {"source_dataset": "d4", "target_dataset": "d2"}
    ]

    assert len(data) == 2, f"Expected exactly 2 pairs in {path}, got {len(data)}"

    for expected in expected_pairs:
        assert expected in data, f"Missing expected pair {expected} in {path}"


def test_run_pipeline_script_exists_and_executable():
    """Test that the bash wrapper script exists and is executable."""
    path = "/home/user/run_pipeline.sh"
    assert os.path.exists(path), f"Script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."


def test_graph_query_is_python_script():
    assert os.path.isfile(GRAPH), f"Python graph query {GRAPH} does not exist."
    assert os.path.getsize(GRAPH) > 0, f"Python graph query {GRAPH} is empty."
    result = subprocess.run(
        ["python3", "-m", "py_compile", GRAPH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"{GRAPH} is not valid Python: {result.stderr}"


def test_pipeline_recomputes_for_unseen_metadata():
    token = uuid.uuid4().hex
    d1 = f"top_alpha_{token}"
    d2 = f"top_beta_{token}"
    e1 = f"neighbor_alpha_{token}"
    e2 = f"neighbor_beta_{token}"
    p1, p2, p3, p4 = [f"paper_{i}_{token}" for i in range(4)]
    records = [
        {"paper_id": p1, "citation_count": 200, "datasets": [d1], "citations": []},
        {"paper_id": p2, "citation_count": 10, "datasets": [e1], "citations": [p1]},
        {"paper_id": p3, "citation_count": 180, "datasets": [d2], "citations": []},
        {"paper_id": p4, "citation_count": 10, "datasets": [e2], "citations": [p3]},
    ]
    expected_top, expected_pairs = expected_for(records)

    with open(METADATA, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    for path in (TOP, FINAL):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run_pipeline()
    assert result.returncode == 0, (
        f"Pipeline failed on unseen metadata. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert has_valid_line(result.stdout), "Pipeline did not print VALID on successful validation"

    actual_top = load_json(TOP)
    assert actual_top == expected_top, f"Expected top datasets {expected_top}, got {actual_top}"
    assert all(isinstance(item, str) for item in actual_top)

    actual_final = load_json(FINAL)
    jsonschema.validate(actual_final, SCHEMA)
    actual_pairs = {
        (item["source_dataset"], item["target_dataset"])
        for item in actual_final
    }
    assert len(actual_final) == len(expected_pairs)
    assert actual_pairs == expected_pairs, f"Expected pairs {expected_pairs}, got {actual_pairs}"


def test_wrapper_runs_graph_query_and_rejects_schema_invalid_output():
    with open(GRAPH, "rb") as f:
        original_graph = f.read()
    original_mode = stat.S_IMODE(os.stat(GRAPH).st_mode)
    marker = f"/tmp/graph_query_called_{uuid.uuid4().hex}"
    stub = f'''#!/usr/bin/env python3
from pathlib import Path
Path({marker!r}).write_text("called", encoding="utf-8")
Path({FINAL!r}).write_text('[{{"source_dataset":"broken"}}]\\n', encoding="utf-8")
print('[{{"source_dataset":"broken"}}]')
'''
    try:
        with open(GRAPH, "w", encoding="utf-8") as f:
            f.write(stub)
        os.chmod(GRAPH, 0o755)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

        result = run_pipeline()
        assert os.path.exists(marker), "run_pipeline.sh did not execute graph_query.py"
        assert result.returncode == 1, (
            "run_pipeline.sh must exit with code 1 when graph output violates the required schema; "
            f"got {result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert not has_valid_line(result.stdout), "Pipeline printed VALID for schema-invalid output"
    finally:
        with open(GRAPH, "wb") as f:
            f.write(original_graph)
        os.chmod(GRAPH, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
