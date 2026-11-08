#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import stat
import subprocess

import pytest

BASE = "/home/user/log_pipeline"
SCRIPT = os.path.join(BASE, "reconstruct_timeline.py")
OUTPUT = os.path.join(BASE, "merged_timeline.json")
BINARY = "/app/score_timeline"

EXPECTED = {
    "A1": {"service": "Alpha", "event_id": "A1", "parent_event_id": "B1", "original_ts": 1000.0},
    "A2": {"service": "Alpha", "event_id": "A2", "parent_event_id": None, "original_ts": 1001.0},
    "B1": {"service": "Beta", "event_id": "B1", "parent_event_id": "A1", "original_ts": 1000.5},
    "B2": {"service": "Beta", "event_id": "B2", "parent_event_id": "A2", "original_ts": 1001.5},
    "G1": {"service": "Gamma", "event_id": "G1", "parent_event_id": "B2", "original_ts": 1002.0},
}


def read_source_logs():
    records = []
    for name in ("service_alpha.log", "service_beta.log", "service_gamma.log"):
        path = os.path.join(BASE, name)
        assert os.path.isfile(path), f"Missing source log: {path}"
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    records.append(json.loads(line))
    return records


def test_pipeline_and_timeline():
    assert os.path.isfile(SCRIPT), f"Expected implementation {SCRIPT} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), "reconstruct_timeline.py must be a regular file."

    # Ensure the task inputs were not emptied or rewritten to make a vacuous output pass.
    source = read_source_logs()
    assert len(source) == len(EXPECTED)
    assert len({item.get("event_id") for item in source}) == len(source)
    assert {item["event_id"]: item for item in source} == EXPECTED

    # The submitted implementation itself must terminate and freshly generate the artifact.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd=BASE,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("reconstruct_timeline.py did not terminate; the causal cycle is still unresolved.")
    assert result.returncode == 0, (
        f"reconstruct_timeline.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing."
    assert stat.S_ISREG(os.lstat(OUTPUT).st_mode), "merged_timeline.json must be a regular file."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {OUTPUT} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "The JSON file must contain an array of objects."
    assert len(data) == len(EXPECTED), "The timeline must contain every source event exactly once."
    assert all(isinstance(item, dict) for item in data), "Every timeline entry must be an object."

    ids = [item.get("event_id") for item in data]
    assert len(set(ids)) == len(ids), "Timeline event IDs must not be duplicated."
    assert set(ids) == set(EXPECTED), "Timeline events must exactly match the source logs."
    by_id = {item["event_id"]: item for item in data}

    for event_id, expected in EXPECTED.items():
        item = by_id[event_id]
        for field in ("service", "event_id", "parent_event_id", "original_ts", "corrected_ts"):
            assert field in item, f"Event {event_id} is missing required field {field}."
        assert item["service"] == expected["service"]
        assert item["original_ts"] == expected["original_ts"]
        assert not isinstance(item["corrected_ts"], bool)
        assert isinstance(item["corrected_ts"], (int, float))
        assert math.isfinite(float(item["corrected_ts"])), f"Event {event_id} has a non-finite corrected timestamp."

    # A1 <-> B1 is an impossible strict-order cycle. Exactly one edge must be
    # removed to break that retry cycle; all other source dependencies are preserved.
    for event_id in ("A2", "B2", "G1"):
        assert by_id[event_id]["parent_event_id"] == EXPECTED[event_id]["parent_event_id"]
    removed_cycle_edges = 0
    for event_id in ("A1", "B1"):
        actual = by_id[event_id]["parent_event_id"]
        expected_parent = EXPECTED[event_id]["parent_event_id"]
        assert actual in (expected_parent, None), "Only a cyclic dependency may be removed."
        removed_cycle_edges += actual is None
    assert removed_cycle_edges == 1, "Break exactly one edge of the A1/B1 cycle."

    corrected = [float(item["corrected_ts"]) for item in data]
    assert corrected == sorted(corrected), "The JSON array must be sorted by corrected timestamp."

    for item in data:
        parent = item["parent_event_id"]
        if parent is not None:
            assert parent in by_id, f"Unknown parent event {parent}."
            assert float(by_id[parent]["corrected_ts"]) < float(item["corrected_ts"]), (
                f"Parent {parent} must strictly precede child {item['event_id']}."
            )

    assert os.path.isfile(BINARY), f"Evaluation binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Evaluation binary {BINARY} is not executable."
    try:
        scored = subprocess.run(
            [BINARY, OUTPUT], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The evaluation binary timed out.")
    assert scored.returncode == 0, f"Evaluation binary failed: {scored.stderr}"
    match = re.search(r"SCORE:\s*([\d.]+)", scored.stdout)
    assert match is not None, f"Could not parse SCORE from binary output. Output was: {scored.stdout}"
    score = float(match.group(1))
    assert score >= 95.0, f"Score {score} is less than the required threshold of 95.0."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
