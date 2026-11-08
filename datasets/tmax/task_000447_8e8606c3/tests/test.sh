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
import sys

import pytest
import requests

APP_DIR = "/home/user/app"


def recurrence(alpha, beta, salt, n):
    if n == 0:
        return 0
    if n == 1:
        return 1
    prev2, prev1 = 0, 1
    for _ in range(2, n + 1):
        prev2, prev1 = prev1, alpha * prev1 + beta * prev2 + salt
    return prev1


def load_math_engine():
    path = os.path.join(APP_DIR, "math_engine.py")
    assert os.path.isfile(path), f"File {path} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_math_engine", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_env_file_recovered():
    """Verify that the SECRET_SALT was recovered and placed in .env."""
    env_path = "/home/user/app/.env"
    assert os.path.isfile(env_path), f"File {env_path} does not exist."

    with open(env_path, "r") as f:
        content = f.read()

    assert "SECRET_SALT=42" in content, "SECRET_SALT=42 is missing from the .env file."


def test_math_engine_implements_correct_recurrence():
    """Exercise the submitted math engine against independently derived answers."""
    engine = load_math_engine()
    assert callable(getattr(engine, "compute", None)), "math_engine.compute is missing or not callable."

    cases = [(3, 5, 42, 100), (1, 1, 0, 20), (-2, 4, 7, 13)]
    rng = secrets.SystemRandom()
    for _ in range(12):
        cases.append((rng.randint(-7, 9), rng.randint(-7, 9), rng.randint(-20, 50), rng.randint(2, 35)))

    for alpha, beta, salt, n in cases:
        expected = recurrence(alpha, beta, salt, n)
        actual = engine.compute(alpha, beta, salt, n)
        assert actual == expected, (
            f"compute({alpha}, {beta}, {salt}, {n}) returned {actual}; expected {expected}."
        )


def test_urandom_descriptor_is_not_left_unclosed():
    """Reject the original unclosed /dev/urandom descriptor in the request handler."""
    server_path = os.path.join(APP_DIR, "server.py")
    assert os.path.isfile(server_path), f"File {server_path} does not exist."
    with open(server_path, "r") as f:
        tree = ast.parse(f.read(), filename=server_path)

    parents = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node

    def containing_function(node):
        while node in parents:
            node = parents[node]
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                return node
        return None

    def is_context_managed(call):
        node = call
        while node in parents:
            node = parents[node]
            if isinstance(node, (ast.With, ast.AsyncWith)):
                return any(item.context_expr is call for item in node.items)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                break
        return False

    for call in [n for n in ast.walk(tree) if isinstance(n, ast.Call)]:
        if not (
            isinstance(call.func, ast.Name)
            and call.func.id == "open"
            and call.args
            and isinstance(call.args[0], ast.Constant)
            and call.args[0].value == "/dev/urandom"
        ):
            continue

        if is_context_managed(call):
            continue

        parent = parents.get(call)
        assigned_name = None
        if isinstance(parent, ast.Assign) and len(parent.targets) == 1 and isinstance(parent.targets[0], ast.Name):
            assigned_name = parent.targets[0].id
        elif isinstance(parent, ast.AnnAssign) and isinstance(parent.target, ast.Name):
            assigned_name = parent.target.id

        function = containing_function(call)
        assert assigned_name is not None and function is not None, (
            "The /dev/urandom descriptor must be removed, context-managed, or explicitly closed."
        )

        close_lines = []
        for node in ast.walk(function):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "close"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id == assigned_name
            ):
                close_lines.append(node.lineno)

        assert close_lines, f"Descriptor {assigned_name!r} opened from /dev/urandom is never closed."
        first_close = min(close_lines)
        premature_returns = [
            node.lineno for node in ast.walk(function)
            if isinstance(node, ast.Return) and call.lineno < node.lineno < first_close
        ]
        assert not premature_returns, (
            f"Descriptor {assigned_name!r} can be leaked by a return before close() on line {first_close}."
        )


def test_server_processing_and_fd_leak_fixed():
    """
    Verify that the server is running, returns the exact recurrence value,
    and survives more than 10 requests.
    """
    url = "http://127.0.0.1:8080/process"
    audio_path = "/app/test_audio.wav"

    assert os.path.isfile(audio_path), f"Test audio file {audio_path} is missing."

    with open(audio_path, "rb") as f:
        audio_data = f.read()

    expected = recurrence(3, 5, 42, 100)
    results = set()

    # Preserve the original 15-request liveness check while exact-checking every answer.
    for i in range(15):
        try:
            response = requests.post(url, data=audio_data, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Request {i+1}/15 failed: {e}. The server might have crashed due to the FD leak.")

        assert response.status_code == 200, f"Request {i+1}/15 returned status {response.status_code}: {response.text}"

        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Request {i+1}/15 did not return valid JSON. Response: {response.text}")

        assert "result" in data, f"Response JSON missing 'result' key: {data}"
        assert data["result"] == expected, (
            f"Request {i+1}/15 returned {data['result']}; expected exact 100th term {expected}."
        )
        results.add(data["result"])

    assert len(results) == 1, f"Expected consistent results across requests, but got multiple: {results}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
