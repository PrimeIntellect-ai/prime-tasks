#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from datetime import datetime, timezone

import pytest

ORIGINAL_LOG = (
    b"[INFO] 2023-10-25T21:00:00Z User login\n"
    b"[ERROR] 2023-10-25T22:30:00+0000 Database timeout\n"
    b"[INFO] 2023-10-26T01:30:00+0300 User logout\n"
    b"[WARN] 2023-10-25T23:45:00.123Z High memory usage\n"
    b"[INFO] 2023-10-26T00:10:00Z System update\n"
)


def expected_records(log_bytes):
    records = []
    for raw_line in log_bytes.decode().splitlines():
        if not raw_line.strip():
            continue
        level_part, rest = raw_line.split("]", 1)
        level = level_part[1:]
        timestamp_text, message = rest.strip().split(" ", 1)
        parsed = datetime.fromisoformat(timestamp_text.replace("Z", "+00:00"))
        if parsed.astimezone(timezone.utc).date().isoformat() == "2023-10-25":
            records.append({
                "timestamp": parsed.isoformat(),
                "level": level,
                "message": message,
            })
    return records


def load_results():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"File not found: {results_path}"
    with open(results_path, "r") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON")


def test_run_test_sh_passes():
    """Verify that running the test script passes successfully."""
    script_path = "/home/user/run_test.sh"
    assert os.path.isfile(script_path), f"File not found: {script_path}"

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_test.sh failed with output: {result.stdout}\n{result.stderr}"
    assert "Build Passed." in result.stdout, "run_test.sh did not print 'Build Passed.'"


def test_results_json_content():
    """Verify that results.json has the correct 4 complete events."""
    with open("/home/user/server_logs.txt", "rb") as handle:
        source = handle.read()
    assert source == ORIGINAL_LOG, "server_logs.txt must be left unchanged"

    results = load_results()
    assert isinstance(results, list), "results.json should contain a JSON array"
    assert len(results) == 4, f"Expected exactly 4 events in results.json, found {len(results)}"

    expected_messages = {
        "User login",
        "Database timeout",
        "User logout",
        "High memory usage",
    }
    actual_messages = {item.get("message") for item in results}
    assert expected_messages.issubset(actual_messages), f"Missing expected events. Expected messages: {expected_messages}, Found: {actual_messages}"

    assert results == expected_records(ORIGINAL_LOG), (
        "Every result must have the timestamp, level, and message from its source "
        "record, and selection must use the timestamp's UTC date"
    )


def test_analyzer_parses_and_filters_fresh_log_data():
    analyzer = "/home/user/log_analyzer.py"
    log_path = "/home/user/server_logs.txt"
    results_path = "/home/user/results.json"
    assert os.path.isfile(analyzer), f"File not found: {analyzer}"

    token = secrets.token_hex(12)
    fresh_log = (
        f"[INFO] 2023-10-25T10:11:12Z Included Z {token}\n"
        f"[ERROR] 2023-10-25T22:30:01+0000 Included compact offset {token}\n"
        f"[INFO] 2023-10-26T01:15:02+0300 Included after UTC conversion {token}\n"
        f"[WARN] 2023-10-25T23:45:03.456Z Included fractional {token}\n"
        f"[INFO] 2023-10-25T01:00:04+0300 Excluded previous UTC date {token}\n"
        f"[ERROR] 2023-10-26T00:10:05Z Excluded next UTC date {token}\n"
    ).encode()
    expected = expected_records(fresh_log)

    with open(log_path, "rb") as handle:
        saved_log = handle.read()
    had_results = os.path.exists(results_path)
    saved_results = None
    if had_results:
        with open(results_path, "rb") as handle:
            saved_results = handle.read()

    try:
        with open(log_path, "wb") as handle:
            handle.write(fresh_log)
        if os.path.exists(results_path):
            os.remove(results_path)

        completed = subprocess.run(
            ["python3", analyzer], capture_output=True, text=True, timeout=15
        )
        assert completed.returncode == 0, (
            f"log_analyzer.py failed on valid log records:\n"
            f"{completed.stdout}\n{completed.stderr}"
        )
        with open(log_path, "rb") as handle:
            assert handle.read() == fresh_log, "log_analyzer.py must not modify server_logs.txt"

        actual = load_results()
        assert isinstance(actual, list), "results.json should contain a JSON array"
        assert actual == expected, (
            "Analyzer output did not preserve complete source records or did not "
            "filter them by their UTC date"
        )
    finally:
        with open(log_path, "wb") as handle:
            handle.write(saved_log)
        if had_results:
            with open(results_path, "wb") as handle:
                handle.write(saved_results)
        elif os.path.exists(results_path):
            os.remove(results_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
