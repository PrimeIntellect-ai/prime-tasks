#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest


def parse_program_output(stdout):
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Compiled Rust program did not print valid JSON: {exc}\nOutput: {stdout!r}")

    assert isinstance(data, dict), "Compiled Rust program must print a single JSON object."
    assert set(data.keys()) == {"cwe", "blocked_ip"}, (
        "Program output must contain exactly the 'cwe' and 'blocked_ip' keys."
    )
    return data


@pytest.fixture(scope="module")
def compiled_solution():
    source = "/home/user/solution.rs"
    assert os.path.isfile(source), f"File {source} does not exist. The task requires writing a Rust program here."

    build_dir = tempfile.mkdtemp(prefix="solution-build-")
    binary = os.path.join(build_dir, "solution")
    try:
        result = subprocess.run(
            ["rustc", source, "-o", binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"solution.rs failed to compile with rustc:\n{result.stderr}"
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "rustc did not produce an executable."
        yield binary
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def run_solution(binary):
    result = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled Rust program exited with status {result.returncode}:\n{result.stderr}"
    )
    return parse_program_output(result.stdout)


def test_solution_rs_exists():
    path = "/home/user/solution.rs"
    assert os.path.isfile(path), f"File {path} does not exist. The task requires writing a Rust program here."


def test_result_json_exists_and_correct():
    path = "/home/user/result.json"
    assert os.path.isfile(path), f"File {path} does not exist. Did you redirect the output of your Rust program?"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert isinstance(data, dict), f"File {path} should contain a JSON object."
    assert "cwe" in data, f"Key 'cwe' missing in {path}."
    assert "blocked_ip" in data, f"Key 'blocked_ip' missing in {path}."

    expected_cwe = "CWE-22"
    expected_ip = "172.16.0.42"

    assert data["cwe"] == expected_cwe, f"Expected 'cwe' to be '{expected_cwe}', but got '{data['cwe']}'."
    assert data["blocked_ip"] == expected_ip, f"Expected 'blocked_ip' to be '{expected_ip}', but got '{data['blocked_ip']}'."


def test_compiled_program_on_original_traffic(compiled_solution):
    data = run_solution(compiled_solution)
    assert data["cwe"] == "CWE-22"
    assert data["blocked_ip"] == "172.16.0.42"


def test_programmatically_parses_changed_traffic(compiled_solution):
    traffic_path = "/home/user/traffic.json"
    with open(traffic_path, "rb") as f:
        original_traffic = f.read()

    attacker_ip = f"198.51.100.{secrets.randbelow(253) + 1}"
    marker = secrets.token_hex(6)
    events = [
        {
            "ip": "203.0.113.10",
            "method": "POST",
            "path": "/api/upload",
            "payload": {"filename": "notes..txt"},
        },
        {
            "ip": attacker_ip,
            "method": "POST",
            "path": "/api/upload",
            "payload": {"filename": f"../../../../tmp/{marker}"},
        },
        {
            "ip": "203.0.113.27",
            "method": "POST",
            "path": "/api/upload",
            "payload": {"filename": f"photo_{marker}.png"},
        },
    ]
    random.SystemRandom().shuffle(events)

    expected_ips = [
        event["ip"]
        for event in events
        if "../" in event["payload"]["filename"]
    ]
    assert len(expected_ips) == 1
    expected_ip = expected_ips[0]

    try:
        with open(traffic_path, "w") as f:
            json.dump(events, f, indent=2)
        data = run_solution(compiled_solution)
    finally:
        with open(traffic_path, "wb") as f:
            f.write(original_traffic)

    assert data["cwe"] == "CWE-22"
    assert data["blocked_ip"] == expected_ip, (
        "The program did not extract the traversal attacker's IP from the changed traffic log."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
