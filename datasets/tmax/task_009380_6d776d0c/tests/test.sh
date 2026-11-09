#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import pytest

MINIMAL_PAYLOAD_PATH = "/home/user/ticket_1092/minimal_payload.txt"
REPORT_PATH = "/home/user/ticket_1092/report.json"
REPO_PATH = "/home/user/ticket_1092/repo"

def test_minimal_payload_exists_and_correct():
    assert os.path.isfile(MINIMAL_PAYLOAD_PATH), f"Minimal payload file missing at {MINIMAL_PAYLOAD_PATH}"
    with open(MINIMAL_PAYLOAD_PATH, "r") as f:
        content = f.read().strip()

    # The absolute minimal line to trigger the crash is just the METRIC_CRITICAL line.
    assert content == "METRIC_CRITICAL=99", f"Minimal payload content is incorrect. Expected 'METRIC_CRITICAL=99', got '{content}'"

def test_report_json_exists_and_correct():
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file")

    assert "buggy_commit" in report, "Key 'buggy_commit' missing in report.json"
    assert "crashing_function" in report, "Key 'crashing_function' missing in report.json"

    # Get the actual buggy commit hash from the repository
    try:
        buggy_commit = subprocess.check_output(
            ["git", "log", "--grep=Add metric extraction logic", "--format=%H"],
            cwd=REPO_PATH, text=True
        ).strip()
    except Exception as e:
        pytest.fail(f"Could not retrieve buggy commit hash from git: {e}")

    assert report["buggy_commit"] == buggy_commit, f"Incorrect buggy_commit. Expected {buggy_commit}, got {report['buggy_commit']}"
    assert report["crashing_function"] == "extract_metrics", f"Incorrect crashing_function. Expected 'extract_metrics', got {report['crashing_function']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
