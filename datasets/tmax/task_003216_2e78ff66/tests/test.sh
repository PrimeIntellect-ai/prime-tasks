#!/bin/bash
set -e
mkdir -p /logs/verifier
BASE_DIR=/home/user/telemetry_processor

# Verify that the repaired requirements can actually be installed.
if ! (cd "$BASE_DIR" && timeout 300 python3 -m pip install -r requirements.txt); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Execute the requested artifact on the supplied telemetry data. Remove any
# precomputed output first so a stale summary cannot satisfy the checks.
rm -f "$BASE_DIR/summary.json"
if ! (cd "$BASE_DIR" && timeout 30 python3 process.py); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys

import pytest
from packaging.requirements import Requirement

BASE_DIR = "/home/user/telemetry_processor"
SUMMARY_PATH = os.path.join(BASE_DIR, "summary.json")
REQ_PATH = os.path.join(BASE_DIR, "requirements.txt")
PROCESS_PATH = os.path.join(BASE_DIR, "process.py")
DATA_PATH = os.path.join(BASE_DIR, "data.json")


def test_summary_json_exists():
    assert os.path.isfile(SUMMARY_PATH), f"Expected output file {SUMMARY_PATH} does not exist."


def test_summary_json_content():
    with open(SUMMARY_PATH, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_PATH} is not a valid JSON file.")

    expected = {
        "total_events_processed": 5,
        "unique_event_ids": 5,
        "total_value": 150,
    }

    assert summary.get("total_events_processed") == expected["total_events_processed"], \
        f"Expected total_events_processed to be {expected['total_events_processed']}, got {summary.get('total_events_processed')}"
    assert summary.get("unique_event_ids") == expected["unique_event_ids"], \
        f"Expected unique_event_ids to be {expected['unique_event_ids']}, got {summary.get('unique_event_ids')}"
    assert summary.get("total_value") == expected["total_value"], \
        f"Expected total_value to be {expected['total_value']}, got {summary.get('total_value')}"
    assert summary == expected, "summary.json must retain the intended output structure."


def test_requirements_fixed():
    assert os.path.isfile(REQ_PATH), f"Requirements file {REQ_PATH} is missing."
    with open(REQ_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "numpy==1.20.0" not in content, "requirements.txt still contains the conflicting numpy==1.20.0 version."
    assert "numpy" in content.lower(), "requirements.txt must still contain numpy."
    assert "pandas" in content.lower(), "requirements.txt must still contain pandas."

    # The package names must be real active requirement entries, not comments or
    # arbitrary text. Installation itself is performed by test.sh above.
    declared = set()
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue
        try:
            req = Requirement(line)
        except Exception:
            continue
        if req.marker is None or req.marker.evaluate():
            declared.add(req.name.lower())
    assert "numpy" in declared, "numpy must remain an active requirement entry."
    assert "pandas" in declared, "pandas must remain an active requirement entry."

    # Confirm the resulting environment is internally consistent and importable.
    check = subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert check.returncode == 0, check.stdout
    imported = subprocess.run(
        [sys.executable, "-c", "import numpy, pandas"],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert imported.returncode == 0, imported.stdout


def test_process_py_modified():
    assert os.path.isfile(PROCESS_PATH), f"File {PROCESS_PATH} does not exist."

    with open(PROCESS_PATH, "r") as f:
        content = f.read()

    # Preserve the original structural assertions.
    assert "def flatten_events" in content, "process.py is missing flatten_events function."
    assert "def main" in content, "process.py is missing main function."


def _expected_summary(graphs):
    events = []

    def visit(node, seen):
        if not isinstance(node, dict):
            return

        # A malformed node is skipped, but a valid descendant remains part of
        # the graph and must still be visited.
        if "id" not in node or not isinstance(node["id"], str):
            visit(node.get("next"), seen)
            return

        node_id = node["id"]
        if node_id in seen:
            return
        seen.add(node_id)

        value = node.get("value", 0)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            visit(node.get("next"), seen)
            return

        events.append((node_id, value))
        visit(node.get("next"), seen)

    for graph in graphs:
        visit(graph, set())

    return {
        "total_events_processed": len(events),
        "unique_event_ids": len({event_id for event_id, _ in events}),
        "total_value": int(sum(value for _, value in events)),
    }


def test_process_handles_cycles_per_traversal_and_malformed_nodes():
    probe_data = [
        {
            "id": "a",
            "value": 1,
            "next": {
                "id": "b",
                "value": 2,
                "next": {"id": "a", "value": 999},
            },
        },
        {
            "id": "a",
            "value": 10,
            "next": {"id": "b", "value": 20, "next": None},
        },
        {
            "value": 999,
            "next": {"id": "c", "value": 7, "next": None},
        },
        {"id": "d", "next": ["unexpected", "node"]},
        123,
    ]
    expected = _expected_summary(probe_data)

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_summary = None
    if os.path.exists(SUMMARY_PATH):
        with open(SUMMARY_PATH, "rb") as f:
            original_summary = f.read()

    try:
        with open(DATA_PATH, "w") as f:
            json.dump(probe_data, f)
        if os.path.exists(SUMMARY_PATH):
            os.remove(SUMMARY_PATH)

        run = subprocess.run(
            [sys.executable, PROCESS_PATH],
            cwd=BASE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        assert run.returncode == 0, f"process.py failed on cyclic/malformed input:\n{run.stdout}"
        assert os.path.isfile(SUMMARY_PATH), "process.py did not generate summary.json."
        with open(SUMMARY_PATH, "r") as f:
            actual = json.load(f)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_summary is None:
            if os.path.exists(SUMMARY_PATH):
                os.remove(SUMMARY_PATH)
        else:
            with open(SUMMARY_PATH, "wb") as f:
                f.write(original_summary)

    assert actual == expected, f"Expected derived summary {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
