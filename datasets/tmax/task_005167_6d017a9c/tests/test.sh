#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

ORCHESTRATOR = "/home/user/orchestrator.sh"
VARS = "/home/user/vars.env"
TEMPLATE = "/home/user/config.template.json"
CONFIG = "/home/user/config.json"
LOG = "/home/user/pipeline.log"
INTERPOLATE = "/app/bash-serve-config/interpolate.sh"
SERVER = "/app/bash-serve-config/server.sh"
LOG_RE = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Pipeline run complete\. Config generated\.$")


def fetch_json(url, expected, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
                body = response.read().decode("utf-8")
                data = json.loads(body)
                if data == expected:
                    return data
                last_error = AssertionError(
                    f"JSON response did not match expected. Expected: {expected!r}; got: {data!r}"
                )
        except (OSError, urllib.error.URLError, ValueError, AssertionError) as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Server never returned the expected JSON: {last_error}")


def run_orchestrator(expected):
    old_size = os.path.getsize(LOG) if os.path.exists(LOG) else 0
    try:
        result = subprocess.run(
            ["su", "user", "-c", ORCHESTRATOR],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"orchestrator.sh did not finish promptly: {exc}")

    assert result.returncode == 0, (
        f"orchestrator.sh failed with exit code {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    fetch_json("http://127.0.0.1:8080/", expected)

    assert os.path.isfile(CONFIG), f"{CONFIG} is missing"
    with open(CONFIG, encoding="utf-8") as handle:
        generated = json.load(handle)
    assert generated == expected, f"Generated config was {generated!r}, expected {expected!r}"

    assert os.path.isfile(LOG), f"{LOG} is missing"
    with open(LOG, "r", encoding="utf-8") as handle:
        handle.seek(old_size)
        appended = handle.read()
    new_lines = [line for line in appended.splitlines() if line]
    assert any(LOG_RE.fullmatch(line) for line in new_lines), (
        "The run did not append a log entry in the required exact format. "
        f"Appended content: {appended!r}"
    )


def test_orchestrator_exists_and_executable():
    assert os.path.isfile(ORCHESTRATOR), f"{ORCHESTRATOR} is missing"
    assert os.access(ORCHESTRATOR, os.X_OK), f"{ORCHESTRATOR} is not executable"
    for path in (INTERPOLATE, SERVER):
        assert os.path.isfile(path), f"{path} is missing"
        assert os.access(path, os.X_OK), f"{path} is not executable"


def test_original_pipeline_execution_and_server_response():
    with open(VARS, "w", encoding="utf-8") as handle:
        handle.write("DB_HOST=db.example.com\nDB_PORT=5432\nAPI_KEY=secret_123\n")
    with open(VARS, "a", encoding="utf-8") as handle:
        handle.write("\nREGION=us-east-1\n")

    with open(TEMPLATE, "w", encoding="utf-8") as handle:
        handle.write(
            '{\n'
            '  "database": "postgresql://{{ DB_HOST }}:{{ DB_PORT }}/mydb",\n'
            '  "auth": {\n'
            '    "key": "{{ API_KEY }}",\n'
            '    "region": "{{ REGION }}"\n'
            '  }\n'
            '}\n'
        )

    expected = {
        "database": "postgresql://db.example.com:5432/mydb",
        "auth": {"key": "secret_123", "region": "us-east-1"},
    }
    run_orchestrator(expected)


def test_interpolator_handles_multiple_independent_variables():
    token = uuid.uuid4().hex
    env_path = f"/home/user/verifier-{token}.env"
    left = f"left_{token}"
    right = f"right_{token[::-1]}"
    with open(env_path, "w", encoding="utf-8") as handle:
        handle.write(f"LEFT={left}\nRIGHT={right}\n")
    os.chmod(env_path, 0o644)

    source = "before={{ LEFT }};middle={{RIGHT}};again={{ LEFT }};after\n"
    result = subprocess.run(
        ["su", "user", "-c", f"{INTERPOLATE} {env_path}"],
        input=source,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"interpolate.sh failed with {result.returncode}: {result.stderr}"
    )
    assert result.stdout == f"before={left};middle={right};again={left};after\n"


def test_randomized_pipeline_and_missing_variable_imputation():
    token = uuid.uuid4().hex
    left = f"host_{token}"
    right = f"port_{token[-12:]}"
    number = str(int(token[:8], 16))

    with open(VARS, "w", encoding="utf-8") as handle:
        handle.write(f"LEFT={left}\nRIGHT={right}\nNUM={number}\n")

    with open(TEMPLATE, "w", encoding="utf-8") as handle:
        handle.write(
            '{\n'
            '  "combined": "{{ LEFT }}::{{ RIGHT }}::{{ LEFT }}",\n'
            '  "nested": {"missing": "{{ ABSENT }}", "tail": "x{{ RIGHT }}y"},\n'
            '  "number_text": "{{ NUM }}"\n'
            '}\n'
        )

    expected = {
        "combined": f"{left}::{right}::{left}",
        "nested": {"missing": "UNKNOWN", "tail": f"x{right}y"},
        "number_text": number,
    }
    run_orchestrator(expected)


def test_server_honors_nondefault_port_and_serves_requested_file():
    token = uuid.uuid4().hex
    served_path = f"/home/user/server-test-{token}.json"
    expected = {"server_token": token, "value": token[::-1]}
    with open(served_path, "w", encoding="utf-8") as handle:
        json.dump(expected, handle)
    os.chmod(served_path, 0o644)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    proc = subprocess.Popen(
        ["su", "user", "-c", f"PORT={port} {SERVER} {served_path}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        fetch_json(f"http://127.0.0.1:{port}/", expected)
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
