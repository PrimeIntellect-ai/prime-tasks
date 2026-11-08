#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/process_logs.py"
SUMMARY_PATH = "/home/user/diagnostic_summary.json"
APP_LOG_PATH = "/home/user/data/app.log"


def remove_summary():
    if os.path.exists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)


def run_processor(log_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, log_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_logs.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(SUMMARY_PATH), "process_logs.py did not generate diagnostic_summary.json"
    with open(SUMMARY_PATH, "r") as f:
        return json.load(f)


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script file missing or not a regular file: {SCRIPT_PATH}"

    possible_counts = [2, 3, 4, 6, 7]
    record_count = possible_counts[secrets.randbelow(len(possible_counts))]
    nonce = secrets.token_hex(12)

    fd, custom_log = tempfile.mkstemp(prefix="process_logs_test_", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            for i in range(record_count):
                payload = {
                    "event": "message",
                    "sequence": i,
                    "text": f"{nonce}-{i} | middle | tail",
                    "nested": {"value": f"left|{i}|right"},
                }
                f.write(f"2026-01-01T00:00:{i:02d}Z|INFO|{json.dumps(payload)}\n")

        remove_summary()
        custom_summary = run_processor(custom_log)
        assert custom_summary.get("valid") == record_count, (
            f"Expected {record_count} valid pipe-containing records, "
            f"found {custom_summary.get('valid')}"
        )
        assert custom_summary.get("errors") == 0, (
            f"Expected zero errors for valid JSON payloads containing pipes, "
            f"found {custom_summary.get('errors')}"
        )
    finally:
        if os.path.exists(custom_log):
            os.remove(custom_log)

    # Run the exact command required by the task and leave its output in the final state.
    remove_summary()
    official_summary = run_processor(APP_LOG_PATH)
    assert official_summary.get("valid") == 5
    assert official_summary.get("errors") == 0


def test_diagnostic_summary_exists_and_correct():
    summary_path = "/home/user/diagnostic_summary.json"
    assert os.path.exists(summary_path), f"Diagnostic summary file missing: {summary_path}"

    with open(summary_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    assert "valid" in data, "Key 'valid' missing in diagnostic_summary.json"
    assert "errors" in data, "Key 'errors' missing in diagnostic_summary.json"

    assert data["valid"] == 5, f"Expected 5 valid records, found {data['valid']}"
    assert data["errors"] == 0, f"Expected 0 error records, found {data['errors']}"


def test_app_log_untouched():
    log_file_path = "/home/user/data/app.log"
    assert os.path.exists(log_file_path), f"Log file missing: {log_file_path}"

    with open(log_file_path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 5, "The log file /home/user/data/app.log appears to have been modified (line count changed)."
    assert "hello | world" in lines[2], "The log file /home/user/data/app.log appears to have been modified."


def test_process_logs_script_exists():
    script_file_path = "/home/user/process_logs.py"
    assert os.path.exists(script_file_path), f"Script file missing: {script_file_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
