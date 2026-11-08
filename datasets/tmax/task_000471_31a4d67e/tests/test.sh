#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import subprocess
import sys
import threading

import pytest
import requests

APP_DIR = "/app/data_aggregator-1.0.0"
SETUP_PATH = os.path.join(APP_DIR, "setup.py")
SERVER_PATH = os.path.join(APP_DIR, "data_aggregator", "server.py")
URL = "http://127.0.0.1:8080/process"
HEADERS = {
    "X-API-Key": "secret-ops-token",
    "Content-Type": "application/json",
}


def test_setup_py_fixed_and_package_installs():
    """Verify the original dependency check and that pip install . actually succeeds."""
    assert os.path.isfile(SETUP_PATH), f"File {SETUP_PATH} does not exist"

    with open(SETUP_PATH, "r") as f:
        content = f.read()

    assert "urllib3==1.24.0" not in content, (
        "setup.py still contains the conflicting urllib3==1.24.0 dependency"
    )

    completed = subprocess.run(
        [sys.executable, "-m", "pip", "install", ".", "--no-input"],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert completed.returncode == 0, f"pip install . failed:\n{completed.stdout}"

    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import data_aggregator; "
            "from importlib.metadata import distribution; "
            "d=distribution('data_aggregator'); "
            "assert d.version == '1.0.0'; "
            "print(data_aggregator.__file__)",
        ],
        cwd="/tmp",
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert probe.returncode == 0, (
        "The installed data_aggregator package could not be imported outside its source tree:\n"
        + probe.stdout
    )


def _load_server_module():
    spec = importlib.util.spec_from_file_location("submitted_data_aggregator_server", SERVER_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_server_py_has_effective_assertion():
    """Keep the original text check, then verify an effective first-statement assertion."""
    assert os.path.isfile(SERVER_PATH), f"File {SERVER_PATH} does not exist"

    with open(SERVER_PATH, "r") as f:
        content = f.read()

    assert "assert isinstance(payload, dict)" in content, (
        "server.py is missing the required assertion: assert isinstance(payload, dict)"
    )

    tree = ast.parse(content, filename=SERVER_PATH)
    functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "process_payload"
    ]
    assert len(functions) == 1, "Expected exactly one process_payload function"

    body = list(functions[0].body)
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
            and isinstance(body[0].value.value, str):
        body = body[1:]
    assert body and isinstance(body[0], ast.Assert), (
        "The payload type assertion must execute before processing"
    )

    assertion = body[0].test
    assert (
        isinstance(assertion, ast.Call)
        and isinstance(assertion.func, ast.Name)
        and assertion.func.id == "isinstance"
        and len(assertion.args) == 2
        and isinstance(assertion.args[0], ast.Name)
        and assertion.args[0].id == "payload"
        and isinstance(assertion.args[1], ast.Name)
        and assertion.args[1].id == "dict"
    ), "process_payload must assert isinstance(payload, dict)"

    module = _load_server_module()
    with pytest.raises(AssertionError):
        module.process_payload(["not", "a", "dict"])


def _run_concurrent(payloads, timeout=5):
    results = [None] * len(payloads)
    exceptions = []

    def make_request(index, payload):
        try:
            results[index] = requests.post(
                URL, json=payload, headers=HEADERS, timeout=timeout
            )
        except Exception as exc:
            exceptions.append(exc)

    threads = [
        threading.Thread(target=make_request, args=(index, payload))
        for index, payload in enumerate(payloads)
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=timeout + 1)

    assert not exceptions, (
        "Exceptions occurred during concurrent requests "
        f"(possible connection refused or timeout): {exceptions}"
    )
    assert all(not thread.is_alive() for thread in threads), (
        "Not all requests completed within the timeout. The server might be deadlocking."
    )
    assert all(response is not None for response in results), (
        "Not all requests produced responses. The server might be deadlocking."
    )
    return results


def _assert_success_response(response, expected_value):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "success", (
        f"Expected status 'success', got {data.get('status')}"
    )
    assert data.get("processed_value") == expected_value, (
        f"Expected processed_value {expected_value!r}, "
        f"got {data.get('processed_value')!r}"
    )


def test_server_concurrent_requests():
    """Retain the original fixed concurrent test."""
    payload = {"data": "test_string", "value": 42}
    results = _run_concurrent([payload.copy() for _ in range(10)])
    for response in results:
        _assert_success_response(response, 42)


def test_server_concurrent_requests_with_unpredictable_values():
    """Exercise request-dependent behavior so a constant-response server cannot pass."""
    nonce = secrets.token_hex(16)
    values = [
        f"{nonce}-{index}-{secrets.token_hex(4)}" if index % 2 == 0
        else secrets.randbelow(2_000_000_000) - 1_000_000_000
        for index in range(12)
    ]
    payloads = [
        {"data": secrets.token_hex(8), "request_index": index, "value": value}
        for index, value in enumerate(values)
    ]
    results = _run_concurrent(payloads)
    for response, expected_value in zip(results, values):
        _assert_success_response(response, expected_value)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
