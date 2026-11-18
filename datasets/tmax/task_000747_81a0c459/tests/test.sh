#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess
import sys

import pytest

SCRIPT_PATH = "/home/user/process.py"
INPUT_PATH = "/home/user/telemetry.json"
OUTPUT_PATH = "/home/user/processed.json"


def encoded_b64(value):
    if isinstance(value, str):
        raw = value.encode("utf-8")
    else:
        raw = json.dumps(value).encode("utf-8")
    return "B64:" + base64.b64encode(raw).decode("ascii")


def encoded_hex(value):
    return "HEX:" + value.encode("utf-8").hex()


def run_processor(raw_data):
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    with open(INPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(raw_data, f)

    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT_PATH} did not terminate; the recursion/loop bug remains.")

    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"The file {OUTPUT_PATH} was not created by the script."

    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON: {exc}")


def test_processor_handles_fresh_nested_inputs():
    token = secrets.token_hex(12)
    first = "first-" + token
    second = "second-" + token
    non_json = "raw-text-" + token

    raw_data = {
        "event": "dynamic-" + token,
        "payload": encoded_b64({
            "nested": encoded_hex(first),
            "deeper": encoded_b64({"value": encoded_hex(second)}),
        }),
        "metadata": encoded_b64(non_json),
        "items": [
            encoded_hex(second),
            encoded_b64([encoded_hex(first), "plain-" + token]),
        ],
    }
    expected = {
        "event": "dynamic-" + token,
        "payload": {
            "nested": first,
            "deeper": {"value": second},
        },
        "metadata": non_json,
        "items": [second, [first, "plain-" + token]],
    }

    assert run_processor(raw_data) == expected


def test_processed_json_exists_and_correct():
    raw_data = {
        "event": "login",
        "payload": "B64:eyAibmVzdGVkIjogIkhFWDo0ODY1NmM2YzZmIiB9",
        "metadata": "B64:bm90X2pzb25fc3RyaW5n",
        "status": "HEX:73756363657373",
    }
    data = run_processor(raw_data)

    expected_data = {
        "event": "login",
        "payload": {
            "nested": "Hello"
        },
        "metadata": "not_json_string",
        "status": "success"
    }

    assert data == expected_data, (
        f"The content of {OUTPUT_PATH} does not match the expected normalized telemetry. "
        f"Expected: {expected_data}, but got: {data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
