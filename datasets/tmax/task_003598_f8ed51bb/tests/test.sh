#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import secrets
import subprocess

import pytest

PROJECT = Path("/home/user/trace_aggregator")
MAIN_RS = PROJECT / "src/main.rs"
LOG_PATH = Path("/home/user/logs/combined.jsonl")
OUTPUT_PATH = Path("/home/user/completed_traces.json")
ROOT_CAUSE_PATH = Path("/home/user/root_cause.txt")
BINARY = PROJECT / "target/debug/trace_aggregator"


def expected_from_events(events):
    active = {}
    completed = []
    for event in events:
        if event["event_type"] == "START":
            active[event["trace_id"]] = event["timestamp"]
        elif event["event_type"] == "END" and event["trace_id"] in active:
            start = active.pop(event["trace_id"])
            completed.append({
                "trace_id": event["trace_id"],
                "total_duration": event["timestamp"] - start,
            })
    return completed


def read_events(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def run_program():
    subprocess.run([str(BINARY)], cwd=PROJECT, check=True, timeout=30)


@pytest.fixture(scope="session", autouse=True)
def build_program():
    assert MAIN_RS.is_file(), f"Source file missing at {MAIN_RS}"
    subprocess.run(["cargo", "clean"], cwd=PROJECT, check=True, timeout=60)
    subprocess.run(["cargo", "build", "--quiet"], cwd=PROJECT, check=True, timeout=120)
    assert BINARY.is_file(), "Cargo did not produce the trace_aggregator executable."
    assert os.access(BINARY, os.X_OK), "Built trace_aggregator artifact is not executable."


def test_root_cause_file():
    """Verify that root_cause.txt contains exactly the correct trace_id."""
    assert ROOT_CAUSE_PATH.is_file(), f"File {ROOT_CAUSE_PATH} does not exist."
    content = ROOT_CAUSE_PATH.read_text().strip()
    assert "req-4" in content, f"Expected 'req-4' in {ROOT_CAUSE_PATH}, but found: {content}"
    assert content == "req-4", f"Expected exactly 'req-4' in {ROOT_CAUSE_PATH}, but found: {content}"


def test_completed_traces_json_is_generated_by_program():
    """Run the rebuilt program and verify complete trace IDs and durations."""
    events = read_events(LOG_PATH)
    expected = expected_from_events(events)

    OUTPUT_PATH.unlink(missing_ok=True)
    run_program()
    assert OUTPUT_PATH.is_file(), f"File {OUTPUT_PATH} does not exist. Did you run the fixed program?"

    try:
        data = json.loads(OUTPUT_PATH.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"{OUTPUT_PATH} is not valid JSON: {exc}")

    assert isinstance(data, list), f"Expected JSON array in {OUTPUT_PATH}, got {type(data)}."
    assert len(data) == 4, f"Expected exactly 4 traces in {OUTPUT_PATH}, but found {len(data)}."

    trace_ids = [item.get("trace_id") for item in data if isinstance(item, dict)]
    expected_traces = {"req-1", "req-2", "req-3", "req-5"}
    assert set(trace_ids) == expected_traces, f"Expected traces {expected_traces}, but found {set(trace_ids)}."
    assert "req-4" not in trace_ids, "req-4 should not be included in the completed traces."
    assert data == expected, f"Trace IDs or total_duration values are incorrect: expected {expected}, got {data}"


def test_program_ignores_unmatched_end_events():
    """Exercise the binary on fresh IDs so an unmatched END cannot be hard-coded."""
    token = secrets.token_hex(8)
    first = f"dynamic-{token}-first"
    second = f"dynamic-{token}-second"
    orphan = f"dynamic-{token}-orphan"
    incomplete = f"dynamic-{token}-incomplete"
    base = 2_000_000_000
    events = [
        {"timestamp": base + 1, "trace_id": first, "event_type": "END"},
        {"timestamp": base + 3, "trace_id": first, "event_type": "START"},
        {"timestamp": base + 11, "trace_id": second, "event_type": "START"},
        {"timestamp": base + 17, "trace_id": first, "event_type": "END"},
        {"timestamp": base + 19, "trace_id": orphan, "event_type": "END"},
        {"timestamp": base + 23, "trace_id": second, "event_type": "END"},
        {"timestamp": base + 29, "trace_id": incomplete, "event_type": "START"},
    ]
    expected = expected_from_events(events)
    original_log = LOG_PATH.read_bytes()
    old_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None

    try:
        LOG_PATH.write_text("".join(json.dumps(event) + "\n" for event in events))
        OUTPUT_PATH.unlink(missing_ok=True)
        run_program()
        assert OUTPUT_PATH.is_file(), "Program did not create completed_traces.json."
        data = json.loads(OUTPUT_PATH.read_text())
        assert data == expected, f"Program did not correctly ignore unmatched END events: expected {expected}, got {data}"
    finally:
        LOG_PATH.write_bytes(original_log)
        if old_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(old_output)


def test_rust_code_fixed():
    """Verify that the original unwrap() panic was removed from main.rs."""
    assert MAIN_RS.is_file(), f"Source file missing at {MAIN_RS}"
    content = MAIN_RS.read_text()
    buggy_line = "let start_time = active_traces.get(&event.trace_id).unwrap();"
    assert buggy_line not in content, "The buggy unwrap() call is still present in main.rs."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
