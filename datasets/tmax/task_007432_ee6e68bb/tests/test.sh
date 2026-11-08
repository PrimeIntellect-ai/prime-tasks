#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess

LOG_FILE = "/home/user/config_changes.log"
JSON_FILE = "/home/user/unique_configs.json"
GO_FILE = "/home/user/analyzer.go"


def derive_expected(log_contents):
    expected_counts = {}
    for line in log_contents.splitlines():
        match = re.search(r"PAYLOAD=\{(.*?)\}", line)
        if match:
            payload = match.group(1)
            sha256_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()
            expected_counts[sha256_hash] = expected_counts.get(sha256_hash, 0) + 1
    return expected_counts


def read_actual():
    assert os.path.exists(JSON_FILE), f"The output file {JSON_FILE} was not created."
    with open(JSON_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f"The file {JSON_FILE} does not contain valid JSON.")


def run_analyzer():
    result = subprocess.run(
        ["go", "run", GO_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"Running {GO_FILE} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_unique_configs_json_exists_and_correct_and_is_generated_by_go_program():
    assert os.path.exists(LOG_FILE), f"The log file {LOG_FILE} is missing. Setup might have been corrupted."
    assert os.path.exists(JSON_FILE), f"The output file {JSON_FILE} was not created."

    with open(LOG_FILE, "r") as f:
        original_log_text = f.read()
    expected_counts = derive_expected(original_log_text)
    actual_data = read_actual()
    assert actual_data == expected_counts, (
        f"The contents of {JSON_FILE} do not match the expected counts.\n"
        f"Expected: {expected_counts}\nActual: {actual_data}"
    )

    assert os.path.isfile(GO_FILE), f"The required Go source file {GO_FILE} is missing."

    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    with open(JSON_FILE, "rb") as f:
        original_json = f.read()

    try:
        os.remove(JSON_FILE)
        run_analyzer()
        regenerated = read_actual()
        assert regenerated == expected_counts, (
            f"Executing {GO_FILE} on the original log produced incorrect data.\n"
            f"Expected: {expected_counts}\nActual: {regenerated}"
        )

        token = secrets.token_hex(12)
        payload_a = f"mode=dynamic-{token};workers=2;"
        payload_b = f"feature={token};enabled=true;"
        payload_c = f"release={token[::-1]};replicas=7;"
        payloads = [payload_a, payload_b, payload_a, payload_c, payload_b, payload_a]
        synthetic_lines = [
            f"[2026-01-01 00:00:0{i}] IP=192.0.2.{i + 1} PAYLOAD={{{payload}}}"
            for i, payload in enumerate(payloads)
        ]
        synthetic_log = "\n".join(synthetic_lines) + "\n"

        with open(LOG_FILE, "w") as f:
            f.write(synthetic_log)
        if os.path.exists(JSON_FILE):
            os.remove(JSON_FILE)

        run_analyzer()
        synthetic_expected = derive_expected(synthetic_log)
        synthetic_actual = read_actual()
        assert synthetic_actual == synthetic_expected, (
            f"Executing {GO_FILE} on a fresh log produced incorrect data.\n"
            f"Expected: {synthetic_expected}\nActual: {synthetic_actual}"
        )
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        with open(JSON_FILE, "wb") as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
