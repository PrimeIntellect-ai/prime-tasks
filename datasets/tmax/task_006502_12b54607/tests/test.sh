#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import hashlib
import json
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
RAW_EVENTS_PATH = "/home/user/raw_events.log"
HASHES_PATH = "/home/user/hashes.txt"
ALERTS_PATH = "/home/user/alerts.txt"


def get_expected_messages():
    # We recompute from the expected raw events
    raw_events = """2023-10-01T10:00:00 [ERROR] {"message": "DB connection timeout", "code": 500}
2023-10-01T10:01:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}
2023-10-01T10:02:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}
2023-10-01T10:03:00 [WARN] {"message": "High CPU usage detected", "code": 300}
2023-10-01T10:04:00 [ERROR] {"message": "CRITICAL: DB connection timout", "code": 500}
2023-10-01T10:05:00 [INFO] {"message": "System restart initiated", "code": 200}
2023-10-01T10:06:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}"""

    messages = []
    for line in raw_events.strip().split('\n'):
        json_str = line.split(' ', 2)[2]
        data = json.loads(json_str)
        messages.append(data['message'])
    return list(set(messages))


def get_expected_hashes():
    messages = get_expected_messages()
    hashes = [hashlib.md5(m.encode('utf-8')).hexdigest() for m in messages]
    return sorted(hashes)


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def get_expected_alerts():
    messages = get_expected_messages()
    target = "CRITICAL: DB connection timeout"
    alerts = [m for m in messages if levenshtein_distance(m, target) <= 5]
    return sorted(alerts)


def run_pipeline():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"The pipeline exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def read_output(path):
    assert os.path.exists(path), f"The file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip().splitlines()


def test_pipeline_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    # Outputs must be produced by executing the submitted pipeline, not merely
    # left behind or hardcoded in advance.
    for path in (HASHES_PATH, ALERTS_PATH):
        if os.path.lexists(path):
            os.remove(path)
    run_pipeline()
    assert os.path.isfile(HASHES_PATH), f"The pipeline did not create {HASHES_PATH}."
    assert os.path.isfile(ALERTS_PATH), f"The pipeline did not create {ALERTS_PATH}."


def test_cronjob_file():
    cronjob_path = "/home/user/cronjob.txt"
    assert os.path.exists(cronjob_path), f"The file {cronjob_path} does not exist."
    with open(cronjob_path, "r") as f:
        content = f.read().strip()

    # Check if it runs every 15 minutes and calls the pipeline script
    assert "/home/user/pipeline.sh" in content, f"The cronjob does not call /home/user/pipeline.sh. Found: {content}"

    # Simple regex to check for common "every 15 minutes" cron patterns
    # Matches */15 or 0,15,30,45 in the first field
    is_valid_cron = bool(re.match(r"^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*", content))
    assert is_valid_cron, f"The cronjob syntax does not correctly schedule every 15 minutes. Found: {content}"


def test_hashes_txt():
    hashes_path = HASHES_PATH
    assert os.path.exists(hashes_path), f"The file {hashes_path} does not exist."
    with open(hashes_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_hashes = get_expected_hashes()

    # sometimes students might append empty lines or have different sorting, let's just check exact match as per instructions
    assert content == expected_hashes, f"The contents of {hashes_path} do not match the expected sorted MD5 hashes."


def test_alerts_txt():
    alerts_path = ALERTS_PATH
    assert os.path.exists(alerts_path), f"The file {alerts_path} does not exist."
    with open(alerts_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_alerts = get_expected_alerts()

    assert content == expected_alerts, f"The contents of {alerts_path} do not match the expected filtered alerts."


def test_pipeline_processes_changed_raw_events():
    target = "CRITICAL: DB connection timeout"
    token = secrets.token_hex(6)
    messages = [
        target,
        target + " " + token[:3],
        "CRITICAL: DB connection timeouX",
        "unrelated event " + token,
        "another distinct event " + secrets.token_hex(5),
        target + " " + token[:3],  # duplicate to exercise deduplication
    ]

    lines = []
    for i, message in enumerate(messages):
        payload = json.dumps({"message": message, "code": 100 + i}, ensure_ascii=False)
        lines.append(f"2026-01-02T03:04:{i:02d} [INFO] {payload}")
    with open(RAW_EVENTS_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    for path in (HASHES_PATH, ALERTS_PATH):
        if os.path.lexists(path):
            os.remove(path)
    run_pipeline()

    unique_messages = set(messages)
    expected_hashes = sorted(
        hashlib.md5(message.encode("utf-8")).hexdigest()
        for message in unique_messages
    )
    expected_alerts = sorted(
        message for message in unique_messages
        if levenshtein_distance(message, target) <= 5
    )

    assert read_output(HASHES_PATH) == expected_hashes, (
        "The pipeline did not recompute sorted, deduplicated MD5 hashes from the changed raw_events.log."
    )
    assert read_output(ALERTS_PATH) == expected_alerts, (
        "The pipeline did not recompute the Levenshtein-filtered alerts from the changed raw_events.log."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
