#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

import pytest

REPO = "/home/user/uptime-monitor"


def run_agent(payload):
    fd, input_path = tempfile.mkstemp(prefix="uptime-verifier-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f)

        return subprocess.run(
            ["cargo", "run", "--quiet", "--", "process", input_path],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=60,
        )
    finally:
        os.unlink(input_path)


def assert_endpoint_was_processed(stdout, endpoint_id, timeout):
    pattern = rf"Monitoring\s+{re.escape(endpoint_id)}\s+with\s+timeout\s+{timeout}s\b"
    assert re.search(pattern, stdout), (
        f"Endpoint {endpoint_id!r} with timeout {timeout} was not processed as expected.\n"
        f"stdout:\n{stdout}"
    )


def test_resolution_json_exists_and_valid():
    path = "/home/user/resolution.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    assert "recovered_api_key" in data, f"Key 'recovered_api_key' missing in {path}."
    assert "failing_endpoint_id" in data, f"Key 'failing_endpoint_id' missing in {path}."

    assert data["recovered_api_key"] == "sre-sec-99x1a2b3c", f"Incorrect recovered_api_key in {path}."
    assert data["failing_endpoint_id"] == "ep-0143", f"Incorrect failing_endpoint_id in {path}."


def test_main_source_is_present():
    path = os.path.join(REPO, "src", "main.rs")
    assert os.path.isfile(path), f"File {path} does not exist."
    assert not os.path.islink(path), f"File {path} must be a regular source file, not a symlink."


def test_rust_code_compiles():
    result = subprocess.run(
        ["cargo", "build"],
        cwd=REPO,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stderr}"


def test_rust_code_runs_without_panic():
    result = subprocess.run(
        ["cargo", "run", "--", "process", "endpoints.json"],
        cwd=REPO,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"cargo run failed or panicked:\n{result.stderr}\n{result.stdout}"
    assert "thread 'main' panicked" not in result.stderr, "Rust application panicked during execution."


def test_generated_valid_endpoints_are_actually_processed():
    token = secrets.token_hex(8)
    endpoints = [
        {
            "id": f"verify-{token}-alpha",
            "url": f"https://{token}.example.test/alpha",
            "timeout": 7,
        },
        {
            "id": f"verify-{token}-beta",
            "url": f"https://{token}.example.test/beta",
            "timeout": 41,
        },
    ]

    result = run_agent(endpoints)
    assert result.returncode == 0, f"Agent failed on valid generated endpoints:\n{result.stderr}\n{result.stdout}"
    assert "thread 'main' panicked" not in result.stderr
    for endpoint in endpoints:
        assert_endpoint_was_processed(result.stdout, endpoint["id"], endpoint["timeout"])


def test_generated_negative_timeout_is_handled_gracefully():
    token = secrets.token_hex(8)
    valid = {
        "id": f"verify-{token}-valid",
        "url": f"https://{token}.example.test/valid",
        "timeout": 13,
    }
    invalid = {
        "id": f"verify-{token}-negative",
        "url": f"https://{token}.example.test/negative",
        "timeout": -29,
    }

    result = run_agent([valid, invalid])
    assert result.returncode == 0, f"Agent did not gracefully handle a negative timeout:\n{result.stderr}\n{result.stdout}"
    assert "thread 'main' panicked" not in result.stderr
    assert_endpoint_was_processed(result.stdout, valid["id"], valid["timeout"])
    assert not re.search(rf"Monitoring\s+{re.escape(invalid['id'])}\s+with\s+timeout", result.stdout), (
        "The endpoint with a negative timeout was transformed and monitored instead of being rejected or skipped."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
