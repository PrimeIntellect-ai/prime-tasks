#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone

import pytest

HOME = "/home/user"
GENERATED = [
    f"{HOME}/parsed_logs.json",
    f"{HOME}/grouped_logs.json",
    f"{HOME}/rolling_stats.json",
]


def run(command):
    result = subprocess.run(
        command,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(command)}\n{result.stdout}"
    return result


def load_json(path):
    assert os.path.exists(path), f"{path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r", encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{path} is not valid JSON: {exc}")


def test_scripts_exist():
    expected_scripts = [
        "/home/user/step1_parse.py",
        "/home/user/step2_sort_group.py",
        "/home/user/step3_stats.py"
    ]
    for script in expected_scripts:
        assert os.path.exists(script), f"Expected script {script} is missing."
        assert os.path.isfile(script), f"{script} is not a file."


def test_makefile_exists_and_targets():
    makefile_path = "/home/user/Makefile"
    assert os.path.exists(makefile_path), "Makefile is missing."
    assert os.path.isfile(makefile_path), "Makefile is not a file."

    with open(makefile_path, "r", encoding="utf-8") as f:
        content = f.read()

    targets = ["parse", "group", "stats", "all", "clean"]
    for target in targets:
        assert f"{target}:" in content, f"Target '{target}' is missing from the Makefile."


def test_rolling_stats_exists_and_correct():
    stats_path = "/home/user/rolling_stats.json"
    assert os.path.exists(stats_path), f"{stats_path} is missing."
    assert os.path.isfile(stats_path), f"{stats_path} is not a file."

    with open(stats_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{stats_path} is not valid JSON.")

    assert isinstance(data, dict), f"Expected {stats_path} to contain a JSON object."
    assert "S1" in data, "Session S1 is missing from rolling_stats.json."
    assert "S2" in data, "Session S2 is missing from rolling_stats.json."

    s1_stat = data.get("S1")
    s2_stat = data.get("S2")
    assert isinstance(s1_stat, (int, float)), f"S1 stat must be a number, got {type(s1_stat)}."
    assert isinstance(s2_stat, (int, float)), f"S2 stat must be a number, got {type(s2_stat)}."
    assert abs(s1_stat - 200.0) < 0.01, f"S1 stat is incorrect. Expected ~200.0, got {s1_stat}."
    assert abs(s2_stat - 70.0) < 0.01, f"S2 stat is incorrect. Expected ~70.0, got {s2_stat}."
    assert "" not in data, "Empty session ID was not filtered out."
    assert None not in data, "Null session ID was not filtered out."


def make_dynamic_input():
    token = secrets.token_hex(5)
    session_a = f"alpha_{token}"
    session_b = f"beta_{token}"
    rng = random.SystemRandom()
    base = datetime(2025, 2, 3, 12, 0, tzinfo=timezone.utc)

    def timestamp(seconds):
        return (base + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")

    values_a = [rng.randint(31, 190) for _ in range(5)]
    values_b = [rng.randint(211, 470) for _ in range(4)]
    rows = []
    for offset, value, message in zip(
        [23, 2, 41, 11, 35],
        values_a,
        [
            "ordinary entry",
            "first line\nsecond line\nthird line",
            "contains, a comma",
            'contains a "quoted" word',
            "final alpha entry",
        ],
    ):
        rows.append({
            "timestamp": timestamp(offset),
            "session_id": session_a,
            "response_time": str(value),
            "message": message,
        })
    for offset, value, message in zip(
        [30, 4, 18, 49],
        values_b,
        ["beta end", "beta start\ncontinued", "beta middle", "beta cleanup"],
    ):
        rows.append({
            "timestamp": timestamp(offset),
            "session_id": session_b,
            "response_time": str(value),
            "message": message,
        })

    rows.extend([
        {"timestamp": timestamp(7), "session_id": "", "response_time": "9999", "message": "must be filtered"},
        {"timestamp": timestamp(8), "session_id": "", "response_time": "8888", "message": "missing session\ncontinued"},
    ])
    rng.shuffle(rows)

    with open(f"{HOME}/raw_logs.csv", "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["timestamp", "session_id", "response_time", "message"])
        writer.writeheader()
        writer.writerows(rows)

    valid = [row for row in rows if row["session_id"]]
    return valid, [session_a, session_b]


def record_key(record):
    assert isinstance(record, dict), "Each record must be a JSON object."
    for key in ("timestamp", "session_id", "response_time", "message"):
        assert key in record, f"Record is missing {key}: {record}"
    try:
        response = float(record["response_time"])
    except (TypeError, ValueError):
        pytest.fail(f"Invalid response_time in record: {record}")
    return (str(record["timestamp"]), str(record["session_id"]), response, str(record["message"]))


def validate_parsed(valid_rows):
    data = load_json(f"{HOME}/parsed_logs.json")
    assert isinstance(data, list), "parsed_logs.json must contain a JSON array."
    expected = Counter(record_key(row) for row in valid_rows)
    actual = Counter(record_key(row) for row in data)
    assert actual == expected, "Parsed output did not preserve exactly the valid CSV records."
    assert any("\n" in row["message"] for row in data), "Embedded-newline records were dropped or damaged."


def validate_grouped(valid_rows, sessions):
    data = load_json(f"{HOME}/grouped_logs.json")
    assert isinstance(data, dict), "grouped_logs.json must contain a JSON object."
    assert set(data) == set(sessions), "Grouped output has missing or unexpected session IDs."

    for session in sessions:
        group = data[session]
        assert isinstance(group, list), f"Group {session} must be an array."
        expected_rows = [row for row in valid_rows if row["session_id"] == session]
        assert Counter(record_key(row) for row in group) == Counter(record_key(row) for row in expected_rows)
        timestamps = [str(row["timestamp"]) for row in group]
        assert timestamps == sorted(timestamps), f"Records for {session} are not sorted by timestamp."


def expected_stats(valid_rows, sessions):
    result = {}
    for session in sessions:
        ordered = sorted(
            (row for row in valid_rows if row["session_id"] == session),
            key=lambda row: row["timestamp"],
        )
        values = [float(row["response_time"]) for row in ordered]
        rolling = []
        for index in range(len(values)):
            window = values[max(0, index - 2):index + 1]
            rolling.append(sum(window) / len(window))
        result[session] = round(max(rolling), 2)
    return result


def validate_stats(valid_rows, sessions):
    data = load_json(f"{HOME}/rolling_stats.json")
    assert isinstance(data, dict), "rolling_stats.json must contain a JSON object."
    assert set(data) == set(sessions), "Statistics have missing or unexpected session IDs."
    expected = expected_stats(valid_rows, sessions)
    for session, wanted in expected.items():
        actual = data[session]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"Statistic for {session} is not numeric."
        assert math.isfinite(float(actual)), f"Statistic for {session} is not finite."
        assert abs(float(actual) - wanted) < 0.005, f"Wrong statistic for {session}: expected {wanted}, got {actual}."


def remove_generated():
    for path in GENERATED:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_pipeline_executes_on_unseen_multiline_csv():
    valid_rows, sessions = make_dynamic_input()
    remove_generated()

    run(["python3", f"{HOME}/step1_parse.py"])
    validate_parsed(valid_rows)
    run(["python3", f"{HOME}/step2_sort_group.py"])
    validate_grouped(valid_rows, sessions)
    run(["python3", f"{HOME}/step3_stats.py"])
    validate_stats(valid_rows, sessions)

    run(["make", "clean"])
    assert all(not os.path.exists(path) for path in GENERATED), "make clean did not remove all generated JSON files."

    run(["make", "parse"])
    validate_parsed(valid_rows)

    run(["make", "clean"])
    run(["make", "group"])
    validate_parsed(valid_rows)
    validate_grouped(valid_rows, sessions)

    run(["make", "clean"])
    run(["make", "stats"])
    validate_parsed(valid_rows)
    validate_grouped(valid_rows, sessions)
    validate_stats(valid_rows, sessions)

    run(["make", "clean"])
    run(["make"])
    validate_parsed(valid_rows)
    validate_grouped(valid_rows, sessions)
    validate_stats(valid_rows, sessions)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
