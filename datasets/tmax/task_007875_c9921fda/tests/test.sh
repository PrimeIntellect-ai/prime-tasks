#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from collections import Counter

import pytest


def test_analyze_exists_runs_and_generates_report():
    script_path = "/home/user/analyze.py"
    report_path = "/home/user/report.json"

    assert os.path.isfile(script_path), f"Expected Python script {script_path} is missing."

    # Prevent a stale, pre-created report from satisfying the verifier.
    if os.path.exists(report_path):
        os.remove(report_path)

    try:
        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{script_path} did not finish within 30 seconds.")

    assert result.returncode == 0, (
        f"Running {script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(report_path), f"Expected output file {report_path} is missing after running the script."


def test_report_json_exists_and_content():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Expected output file {report_path} is missing."

    with open(report_path, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    expected_keys = {"shortest_path", "pattern_matches", "top_authors"}
    assert set(report_data.keys()) == expected_keys, f"JSON keys in {report_path} do not match expected keys. Found: {list(report_data.keys())}"

    expected_shortest_path = ["P10", "P9", "P3", "P1"]
    assert report_data["shortest_path"] == expected_shortest_path, f"shortest_path is incorrect. Expected {expected_shortest_path}, got {report_data['shortest_path']}"

    expected_pattern_matches = [
        ["P5", "P3", "P1"],
        ["P9", "P8", "P7"],
        ["P9", "P3", "P1"],
    ]
    actual_pattern_matches = report_data["pattern_matches"]
    assert isinstance(actual_pattern_matches, list), "pattern_matches must be a list."
    assert all(isinstance(chain, list) and len(chain) == 3 for chain in actual_pattern_matches), "Each pattern_matches entry must be a list of exactly 3 paper IDs."
    assert Counter(map(tuple, actual_pattern_matches)) == Counter(map(tuple, expected_pattern_matches)), f"pattern_matches is incorrect. Expected exactly {expected_pattern_matches}, got {actual_pattern_matches}"
    first_ids = [chain[0] for chain in actual_pattern_matches]
    assert first_ids == sorted(first_ids), f"pattern_matches is not sorted by the first paper_id: {actual_pattern_matches}"

    expected_top_authors = ["A1", "A2", "A3"]
    assert report_data["top_authors"] == expected_top_authors, f"top_authors is incorrect. Expected {expected_top_authors}, got {report_data['top_authors']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
