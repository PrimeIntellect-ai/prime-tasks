#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import importlib.util
import json
import math
import os
import random
import signal
import socket
import stat
import subprocess
import sys
import time
import types
import urllib.error
import urllib.request
from contextlib import ExitStack, contextmanager
from unittest.mock import patch

import pytest
from flask import Flask

MATH_SERVICE_DIR = "/home/user/math_service"
SERVER_FILE = os.path.join(MATH_SERVICE_DIR, "server.py")
TEST_FILE = os.path.join(MATH_SERVICE_DIR, "test_server.py")
CI_SCRIPT = os.path.join(MATH_SERVICE_DIR, "ci_run.sh")
URL = "http://127.0.0.1:8080/evaluate"


def test_files_exist():
    assert os.path.isdir(MATH_SERVICE_DIR), f"Directory {MATH_SERVICE_DIR} does not exist."
    assert os.path.isfile(SERVER_FILE), f"File {SERVER_FILE} does not exist."
    assert os.path.isfile(TEST_FILE), f"File {TEST_FILE} does not exist."
    assert os.path.isfile(CI_SCRIPT), f"File {CI_SCRIPT} does not exist."


def test_ci_script_executable():
    st = os.stat(CI_SCRIPT)
    assert st.st_mode & stat.S_IXUSR, f"{CI_SCRIPT} is not executable."


def test_submission_contains_required_tests_and_ci_commands():
    with open(TEST_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=TEST_FILE)
    test_names = [
        n.name.lower() for n in ast.walk(tree)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test_")
    ]
    assert any("valid" in n or "evaluat" in n for n in test_names), "Missing a valid-evaluation pytest test."
    assert any("invalid" in n or "reject" in n for n in test_names), "Missing an invalid-input pytest test."
    assert any("rate" in n or "limit" in n for n in test_names), "Missing a rate-limit pytest test."
    assert "/evaluate" in source, "The pytest suite does not exercise /evaluate."
    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)}
    assert 200 in constants and 400 in constants and 429 in constants, "Tests must assert the required HTTP outcomes."

    imported_patch = any(
        (isinstance(n, ast.ImportFrom) and n.module == "unittest.mock" and
         any(a.name == "patch" for a in n.names)) or
        (isinstance(n, ast.Import) and any(a.name == "unittest.mock" for a in n.names))
        for n in ast.walk(tree)
    )
    patching_time = False
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        call_text = ast.get_source_segment(source, n) or ""
        func_text = ast.get_source_segment(source, n.func) or ""
        if "patch" in func_text and "time" in call_text:
            patching_time = True
            break
    assert imported_patch and patching_time, "Rate-limit tests must use unittest.mock.patch to mock time."

    with open(CI_SCRIPT, "r", encoding="utf-8") as f:
        ci = f.read().lower()
    assert "flask" in ci and "pytest" in ci, "ci_run.sh must install/use flask and pytest."
    assert "test_server.py" in ci, "ci_run.sh must run test_server.py."


def test_ci_script_runs_successfully():
    try:
        result = subprocess.run(
            ["bash", CI_SCRIPT], cwd=MATH_SERVICE_DIR,
            capture_output=True, text=True, timeout=180
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"ci_run.sh timed out.\nSTDOUT:\n{exc.stdout}\nSTDERR:\n{exc.stderr}")
    assert result.returncode == 0, (
        f"ci_run.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def _wait_for_port(proc):
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Server exited during startup with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("Server failed to start on 127.0.0.1:8080")


@contextmanager
def running_server():
    env = os.environ.copy()
    env["FLASK_ENV"] = "production"
    env["FLASK_DEBUG"] = "0"
    proc = subprocess.Popen(
        [sys.executable, SERVER_FILE], cwd=MATH_SERVICE_DIR, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        _wait_for_port(proc)
        yield
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)


def send_encoded(expression):
    payload = base64.b64encode(expression.encode("utf-8")).decode("ascii")
    return send_raw_payload(payload)


def send_raw_payload(payload):
    req = urllib.request.Request(URL, method="POST")
    req.add_header("Content-Type", "application/json")
    body = json.dumps({"payload": payload}).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=body, timeout=3) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def test_original_required_cases():
    with running_server():
        code, data = send_encoded("2 + 2")
        assert code == 200, f"Expected 200 OK, got {code}"
        assert "result" in data, "Response missing 'result' key"
        assert data["result"] == 4, f"Expected result 4, got {data['result']}"

        code, data = send_encoded("import os")
        assert code == 400, f"Expected 400 Bad Request, got {code}"
        assert "error" in data, "Response missing 'error' key"

        code, data = send_encoded("1 / 0")
        assert code == 400, f"Expected 400 Bad Request for division by zero, got {code}"


def test_general_mathematical_evaluation():
    rng = random.SystemRandom()
    a, b, c, d = [rng.randint(2, 40) for _ in range(4)]
    expressions = [
        (f"({a} + {b}) * {c} - {d}", (a + b) * c - d),
        (f"{a}.{b % 10} + {c}.{d % 10}", float(f"{a}.{b % 10}") + float(f"{c}.{d % 10}")),
        (f"({a} * {b}) / ({c} + 1)", (a * b) / (c + 1)),
        (f"-({a} - {b}) * ({c} + {d})", -(a - b) * (c + d)),
        (f"(({a} + {b}) * ({c} - 1)) / {d}", ((a + b) * (c - 1)) / d),
    ]
    with running_server():
        for expression, expected in expressions:
            code, data = send_encoded(expression)
            assert code == 200, f"{expression!r} returned HTTP {code}: {data}"
            assert set(data) == {"result"}, f"Unexpected success response for {expression!r}: {data}"
            assert isinstance(data["result"], (int, float)) and not isinstance(data["result"], bool)
            assert math.isclose(data["result"], expected, rel_tol=1e-10, abs_tol=1e-10), (
                f"Wrong result for {expression!r}: expected {expected}, got {data['result']}"
            )


def test_strict_character_and_base64_validation():
    rng = random.SystemRandom()
    invalid_expressions = [
        f"{rng.randint(1, 99)}a+1",
        f"{rng.randint(1, 99)}[0]",
        f"{rng.randint(1, 99)}_+1",
        f"{rng.randint(1, 99)}**2;",
    ]
    valid_b64_with_garbage = base64.b64encode(b"7 + 8").decode("ascii") + "!"
    with running_server():
        for expression in invalid_expressions:
            code, data = send_encoded(expression)
            assert code == 400, f"Invalid characters in {expression!r} were accepted"
            assert data == {"error": "Invalid input"}, f"Wrong invalid-input response: {data}"
        code, data = send_raw_payload(valid_b64_with_garbage)
        assert code == 400, "Malformed base64 containing trailing garbage was accepted"
        assert data == {"error": "Invalid input"}


def test_exact_black_box_rate_limit():
    with running_server():
        for i in range(5):
            code, data = send_encoded(f"{i + 11} + {i + 3}")
            assert code == 200, f"Request {i + 1} should be allowed, got {code}: {data}"
        code, data = send_encoded("91 - 17")
        assert code == 429, f"The sixth request should return 429, got {code}: {data}"
        assert data == {"error": "Rate limit exceeded"}


class _Clock:
    def __init__(self, value):
        self.value = value

    def time(self):
        return self.value

    def monotonic(self):
        return self.value


class _TimeProxy:
    def __init__(self, real_module, clock):
        self._real = real_module
        self._clock = clock

    def time(self):
        return self._clock.value

    def monotonic(self):
        return self._clock.value

    def __getattr__(self, name):
        return getattr(self._real, name)


def _load_server_module():
    name = f"submitted_server_{os.getpid()}"
    spec = importlib.util.spec_from_file_location(name, SERVER_FILE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    old_cwd = os.getcwd()
    sys.path.insert(0, MATH_SERVICE_DIR)
    try:
        os.chdir(MATH_SERVICE_DIR)
        spec.loader.exec_module(module)
    finally:
        os.chdir(old_cwd)
        sys.path.pop(0)
    return module


def test_rolling_window_with_mocked_clock():
    module = _load_server_module()
    app = getattr(module, "app", None)
    assert isinstance(app, Flask), "server.py must expose its Flask application as app"
    app.testing = True

    clock = _Clock(1000.0)
    patched_clock = False
    with ExitStack() as stack:
        for name, value in list(vars(module).items()):
            if isinstance(value, types.ModuleType) and value.__name__ == "time":
                stack.enter_context(patch.object(module, name, _TimeProxy(value, clock)))
                patched_clock = True
            elif callable(value) and getattr(value, "__module__", None) == "time" and getattr(value, "__name__", "") in {"time", "monotonic"}:
                stack.enter_context(patch.object(module, name, clock.time))
                patched_clock = True
        assert patched_clock, "The rate limiter must use a mockable time/monotonic clock."

        client = app.test_client()
        body = {"payload": base64.b64encode(b"3 + 4").decode("ascii")}
        for i in range(5):
            response = client.post("/evaluate", json=body)
            assert response.status_code == 200, f"Mock-time request {i + 1} was not allowed"
        response = client.post("/evaluate", json=body)
        assert response.status_code == 429
        assert response.get_json() == {"error": "Rate limit exceeded"}

        clock.value += 60.01
        response = client.post("/evaluate", json=body)
        assert response.status_code == 200, "A request was not allowed after the rolling 60-second window expired"
        assert response.get_json()["result"] == 7
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
