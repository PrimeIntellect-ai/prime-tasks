#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess

import pytest

SCRIPT = "/home/user/run_dag.sh"
RAW_LOG = "/home/user/raw_logs/server.log"
FAILED = "/home/user/failed_attempts.txt"
STRUCTURED = "/home/user/structured_data.json"
PIPELINE_LOG = "/home/user/pipeline.log"

SUCCESS_EXTRACT = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] EXTRACT SUCCESS$")
SUCCESS_TRANSFORM = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] TRANSFORM SUCCESS$")
FAILED_EXTRACT = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] EXTRACT FAILED$")


def read_lines(path):
    with open(path, "r") as f:
        return f.read().strip().split("\n")


def run_script():
    return subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def remove_outputs():
    for path in (FAILED, STRUCTURED, PIPELINE_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_pipeline_artifact_and_behavior():
    # Preserve all assertions made by the original verifier against the agent's
    # required initial execution.
    assert os.path.isfile(FAILED), f"File {FAILED} is missing. Did the EXTRACT step run?"
    lines = read_lines(FAILED)
    assert len(lines) == 3, f"Expected 3 lines in {FAILED}, but found {len(lines)}."
    for line in lines:
        assert "Failed password" in line, f"Line missing 'Failed password': {line}"

    assert os.path.isfile(STRUCTURED), f"File {STRUCTURED} is missing. Did the TRANSFORM step run?"
    try:
        with open(STRUCTURED, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {STRUCTURED} does not contain valid JSON.")

    expected_data = [
        {"timestamp": "Jan 15 10:15:22", "user": "admin", "ip": "192.168.1.50"},
        {"timestamp": "Jan 15 10:17:10", "user": "root", "ip": "10.0.0.5"},
        {"timestamp": "Jan 15 10:20:00", "user": "testuser", "ip": "172.16.0.4"},
    ]
    assert isinstance(data, list), f"Expected a JSON array in {STRUCTURED}, but got {type(data).__name__}."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in JSON array, got {len(data)}."
    for i, expected_item in enumerate(expected_data):
        assert data[i] == expected_item, f"Mismatch at index {i} in {STRUCTURED}. Expected {expected_item}, got {data[i]}."

    assert os.path.isfile(PIPELINE_LOG), f"File {PIPELINE_LOG} is missing. Pipeline logging step failed."
    log_lines = read_lines(PIPELINE_LOG)
    assert len(log_lines) == 2, f"Expected exactly 2 lines in {PIPELINE_LOG}, but found {len(log_lines)}."
    assert SUCCESS_EXTRACT.match(log_lines[0]), f"First line of log does not match expected format. Got: {log_lines[0]}"
    assert SUCCESS_TRANSFORM.match(log_lines[1]), f"Second line of log does not match expected format. Got: {log_lines[1]}"

    # The requested artifact must be an executable Bash script.
    script_stat = os.lstat(SCRIPT)
    assert stat.S_ISREG(script_stat.st_mode), f"{SCRIPT} is not a regular file."
    assert script_stat.st_mode & 0o111, f"{SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!\s*(?:/usr/bin/env\s+bash|(?:/usr)?/bin/bash)(?:\s|$)", first_line), \
        f"{SCRIPT} is not an executable Bash script."

    raw_stat = os.stat(RAW_LOG)
    with open(RAW_LOG, "rb") as f:
        original_raw = f.read()

    token = secrets.token_hex(5)
    users = [f"alpha{token}", f"beta{token}", f"gamma{token}", f"delta{token}"]
    events = [
        ("Feb 03 01:02:03", users[0], "203.0.113.17", True),
        ("Mar 14 12:34:56", users[1], "198.51.100.29", False),
        ("Apr 25 23:45:01", users[2], "192.0.2.88", True),
        ("May 09 08:07:06", users[3], "10.44.55.66", False),
    ]
    dynamic_lines = ["Feb 03 01:00:00 host systemd[1]: Started a harmless service."]
    expected_failed = []
    expected_json = []
    for index, (timestamp, user, ip, invalid) in enumerate(events, start=7001):
        user_text = f"invalid user {user}" if invalid else user
        line = f"{timestamp} host sshd[{index}]: Failed password for {user_text} from {ip} port {20000 + index} ssh2"
        dynamic_lines.append(line)
        expected_failed.append(line)
        expected_json.append({"timestamp": timestamp, "user": user, "ip": ip})
        dynamic_lines.append(f"{timestamp} host app[{index}]: ordinary message from 127.0.0.1")

    try:
        # Delete all products, supply verifier-generated input, and actually run
        # the submitted artifact as the unprivileged task user.
        with open(RAW_LOG, "w") as f:
            f.write("\n".join(dynamic_lines) + "\n")
        remove_outputs()
        result = run_script()
        assert result.returncode == 0, \
            f"Pipeline failed on valid input (exit {result.returncode}). stderr: {result.stderr}"

        assert os.path.isfile(FAILED), "The executed EXTRACT step did not create failed_attempts.txt."
        assert read_lines(FAILED) == expected_failed, "EXTRACT did not copy exactly the failed-password input lines in order."

        assert os.path.isfile(STRUCTURED), "The executed TRANSFORM step did not create structured_data.json."
        try:
            with open(STRUCTURED, "r") as f:
                dynamic_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("TRANSFORM output from verifier-generated input is not valid JSON.")
        assert dynamic_data == expected_json, "TRANSFORM did not correctly parse verifier-generated events."
        for item in dynamic_data:
            assert set(item.keys()) == {"timestamp", "user", "ip"}, "JSON objects do not have the exact required keys."

        dynamic_log = read_lines(PIPELINE_LOG)
        assert len(dynamic_log) == 2, "A successful run must log exactly the two ordered steps."
        assert SUCCESS_EXTRACT.match(dynamic_log[0]), f"Invalid EXTRACT success log entry: {dynamic_log[0]}"
        assert SUCCESS_TRANSFORM.match(dynamic_log[1]), f"Invalid TRANSFORM success log entry: {dynamic_log[1]}"

        # Force EXTRACT to fail. TRANSFORM must be conditionally skipped rather
        # than producing a fabricated or empty structured result.
        os.remove(RAW_LOG)
        remove_outputs()
        run_script()
        assert not os.path.exists(STRUCTURED), "TRANSFORM ran even though EXTRACT failed."
        assert os.path.isfile(PIPELINE_LOG), "The failed EXTRACT execution was not monitored."
        failure_log = read_lines(PIPELINE_LOG)
        assert len(failure_log) == 1, "A failed EXTRACT must stop the DAG before TRANSFORM."
        assert FAILED_EXTRACT.match(failure_log[0]), f"Invalid EXTRACT failure log entry: {failure_log[0]}"
    finally:
        with open(RAW_LOG, "wb") as f:
            f.write(original_raw)
        os.chmod(RAW_LOG, stat.S_IMODE(raw_stat.st_mode))
        os.chown(RAW_LOG, raw_stat.st_uid, raw_stat.st_gid)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
