#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import subprocess
from datetime import datetime
import pytest

# Immutable expectations from the original task state. These prevent writable
# repository files, history, and logs from becoming self-authored oracles.
ORIGINAL_EXPECTED = {
    "hidden_config_path": "/home/user/.cache/pipeline_data/fallback_config.json",
    "recovered_key": "super_secret_build_key_77a91",
    "failing_transaction_id": "tx-9942-err",
}

def get_expected_config_path():
    build_script = "/home/user/pipeline/build.py"
    assert os.path.exists(build_script), f"Build script missing at {build_script}"

    with open(build_script, "r") as f:
        content = f.read()

    match = re.search(r"bytes\.fromhex\(['\"]([0-9a-fA-F]+)['\"]\)", content)
    assert match is not None, "Could not find the hex-encoded config path in build.py"

    hex_str = match.group(1)
    return bytes.fromhex(hex_str).decode("utf-8")

def get_expected_secret_key():
    repo_dir = "/home/user/pipeline"
    try:
        out = subprocess.check_output(
            ["git", "-C", repo_dir, "log", "-p"],
            stderr=subprocess.STDOUT,
            text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git log in {repo_dir}: {e.output}")

    match = re.search(r'^\+SECRET_KEY="(.*?)"', out, re.MULTILINE)
    assert match is not None, "Could not find SECRET_KEY addition in git history"
    return match.group(1)

def get_expected_failing_tx():
    events = []

    web_log = "/home/user/pipeline/logs/web.log"
    db_log = "/home/user/pipeline/logs/db.log"

    assert os.path.exists(web_log), f"Missing {web_log}"
    assert os.path.exists(db_log), f"Missing {db_log}"

    with open(web_log, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split("] [")
            ts = parts[0][1:]
            tx_id = parts[2].split("] ")[1]
            events.append((datetime.strptime(ts, "%Y-%m-%d %H:%M:%S"), "WEB", tx_id))

    with open(db_log, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split("] [")
            ts = parts[0][1:]
            tx_id = parts[2].split("] ")[1]
            events.append((datetime.strptime(ts, "%Y-%m-%d %H:%M:%S"), "DB", tx_id))

    events.sort(key=lambda x: x[0])

    tx_state = {}
    for ts, source, tx_id in events:
        if tx_id not in tx_state:
            tx_state[tx_id] = []
        tx_state[tx_id].append(source)

        if tx_state[tx_id] == ["DB"]:
            return tx_id

    pytest.fail("Could not find a timeline anomaly in the logs.")

def test_debug_report_exists_and_correct():
    report_path = "/home/user/debug_report.json"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist. Did you create it?"

    try:
        with open(report_path, "r") as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {report_path} does not contain valid JSON.")

    assert isinstance(report, dict), f"The JSON in {report_path} must be an object/dictionary."

    expected_config_path = get_expected_config_path()
    expected_secret_key = get_expected_secret_key()
    expected_failing_tx = get_expected_failing_tx()

    assert "hidden_config_path" in report, "Missing 'hidden_config_path' key in JSON report."
    assert report["hidden_config_path"] == expected_config_path, \
        f"Incorrect hidden_config_path. Expected {expected_config_path}, got {report['hidden_config_path']}"

    assert "recovered_key" in report, "Missing 'recovered_key' key in JSON report."
    assert report["recovered_key"] == expected_secret_key, \
        f"Incorrect recovered_key. Expected {expected_secret_key}, got {report['recovered_key']}"

    assert "failing_transaction_id" in report, "Missing 'failing_transaction_id' key in JSON report."
    assert report["failing_transaction_id"] == expected_failing_tx, \
        f"Incorrect failing_transaction_id. Expected {expected_failing_tx}, got {report['failing_transaction_id']}"

    # Also validate against immutable values, rather than trusting only the
    # agent-writable build script, Git history, and logs.
    assert report == ORIGINAL_EXPECTED, \
        f"Report does not contain the three answers from the original task state: {report}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
