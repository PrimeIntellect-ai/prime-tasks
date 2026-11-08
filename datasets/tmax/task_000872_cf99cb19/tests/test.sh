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
import concurrent.futures
import importlib.util
import json
import math
import os
import random
import shutil
import socket
import subprocess
import sys
import tempfile
import textwrap
import uuid

import pytest
import requests

REPO = "/home/user/service_repo"
REGRESSION = "/home/user/regression_test.py"


def expected_result(a, b):
    return 42.0 * (a * b) / (a + b + 0.001)


def check_http(a, b):
    url = "http://127.0.0.1:8080/compute"
    payload = {"a": a, "b": b}
    try:
        response = requests.post(url, json=payload, timeout=5)
        response.raise_for_status()
        data = response.json()
        assert "result" in data, "HTTP response missing 'result' key"
        result = float(data["result"])
        expected = expected_result(a, b)
        assert abs(result - expected) < 1e-5, f"HTTP result mismatch for {a}, {b}: expected {expected}, got {result}"
        return True
    except Exception as e:
        return str(e)


def check_tcp(a, b):
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=5) as sock:
            msg = f"{a},{b}\n"
            sock.sendall(msg.encode("utf-8"))
            response = sock.recv(1024).decode("utf-8").strip()
            result = float(response)
            expected = expected_result(a, b)
            assert abs(result - expected) < 1e-5, f"TCP result mismatch for {a}, {b}: expected {expected}, got {result}"
            return True
    except Exception as e:
        return str(e)


def git(*args):
    return subprocess.check_output(["git", "-C", REPO, *args], text=True).strip()


def load_current_service():
    path = os.path.join(REPO, "service.py")
    name = "submitted_service_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_repository_history_and_fix_are_present():
    assert os.path.isdir(os.path.join(REPO, ".git")), "service_repo is no longer a Git repository"
    commits = git("rev-list", "--reverse", "HEAD").splitlines()
    assert len(commits) >= 200, "The original 200-commit history is missing"

    commit_100, commit_101, commit_200 = commits[99], commits[100], commits[199]
    message_101 = git("show", "-s", "--format=%s", commit_101)
    source_100 = git("show", f"{commit_100}:service.py")
    source_101 = git("show", f"{commit_101}:service.py")

    assert message_101 == "Commit 101: refactor caching"
    assert "global temp_val" not in source_100
    assert "global temp_val" in source_101 and "time.sleep" in source_101

    current_path = os.path.join(REPO, "service.py")
    assert os.path.isfile(current_path), "Missing service.py in service_repo"
    current_source = open(current_path, encoding="utf-8").read()
    assert current_source.strip(), "service.py is empty"
    assert git("diff", commit_200, "--", "service.py"), "The faulty latest service.py was not changed"

    # The fixed implementation must be native Python, not a wrapper around the oracle.
    ast.parse(current_source, filename=current_path)
    lowered = current_source.lower()
    assert "/app/oracle_bin" not in current_source
    assert "subprocess" not in lowered and "os.system" not in lowered and "ctypes" not in lowered


def test_repository_compute_is_fixed_under_concurrency():
    module = load_current_service()
    assert callable(getattr(module, "compute", None)), "service.py must provide compute(a, b)"
    inputs = [(1.25 + i * 0.71, 91.0 - i * 0.43) for i in range(80)]

    def invoke(pair):
        a, b = pair
        return float(module.compute(a, b))

    with concurrent.futures.ThreadPoolExecutor(max_workers=40) as executor:
        results = list(executor.map(invoke, inputs))

    for (a, b), result in zip(inputs, results):
        expected = expected_result(a, b)
        assert math.isfinite(result)
        assert abs(result - expected) < 1e-5, f"repository compute mismatch for {a}, {b}: expected {expected}, got {result}"


def make_instrumented_service(path, faulty):
    race_body = """
    global temp_val
    temp_val = a * b
    time.sleep(0.01)
    result = 42.0 * temp_val / (a + b + 0.001)
""" if faulty else """
    time.sleep(0.01)
    result = 42.0 * (a * b) / (a + b + 0.001)
"""
    source = f'''
import atexit
import json
import os
import threading
import time

_lock = threading.Lock()
_active = 0
_calls = 0
_threads = set()
_inputs = set()
_overlap = False
temp_val = 0.0


def compute(a, b):
    global _active, _calls, _overlap
    with _lock:
        _active += 1
        _calls += 1
        _threads.add(threading.get_ident())
        _inputs.add((float(a), float(b)))
        if _active > 1:
            _overlap = True
    try:
{textwrap.indent(race_body, '        ')}
        return result
    finally:
        with _lock:
            _active -= 1


def _write_log():
    target = os.environ.get("REG_LOG")
    if target:
        with open(target, "w") as f:
            json.dump({{"calls": _calls, "threads": len(_threads), "inputs": len(_inputs), "overlap": _overlap}}, f)

atexit.register(_write_log)
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(source)


def run_regression_variant(mode, faulty):
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(REGRESSION, os.path.join(td, "regression_test.py"))
        make_instrumented_service(os.path.join(td, "service.py"), faulty)
        log_path = os.path.join(td, "activity.json")
        env = os.environ.copy()
        env["PYTHONPATH"] = td
        env["REG_LOG"] = log_path
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        if mode == "script":
            command = [sys.executable, os.path.join(td, "regression_test.py")]
        else:
            command = [sys.executable, "-m", "pytest", "-q", os.path.join(td, "regression_test.py")]
        try:
            completed = subprocess.run(command, cwd=td, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            return None, {}, "timed out"
        activity = {}
        if os.path.isfile(log_path):
            try:
                with open(log_path, encoding="utf-8") as f:
                    activity = json.load(f)
            except Exception:
                activity = {}
        return completed.returncode, activity, completed.stdout[-3000:]


def activity_is_concurrent(activity):
    return (activity.get("calls", 0) >= 10 and activity.get("threads", 0) >= 2
            and activity.get("inputs", 0) >= 2 and activity.get("overlap") is True)


def test_regression_test_script_exists():
    path = REGRESSION
    assert os.path.exists(path), f"Missing regression test script at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.path.getsize(path) > 0, f"{path} is empty"
    source = open(path, encoding="utf-8").read()
    ast.parse(source, filename=path)


def test_regression_script_reliably_detects_the_race():
    # Support both a directly executable test script and a pytest-style test file.
    failures = []
    for mode in ("script", "pytest"):
        fixed_rc, fixed_activity, fixed_output = run_regression_variant(mode, faulty=False)
        bad_rc, bad_activity, bad_output = run_regression_variant(mode, faulty=True)
        if (fixed_rc == 0 and bad_rc not in (None, 0)
                and activity_is_concurrent(fixed_activity)
                and activity_is_concurrent(bad_activity)):
            return
        failures.append(
            f"{mode}: fixed_rc={fixed_rc}, bad_rc={bad_rc}, "
            f"fixed_activity={fixed_activity}, bad_activity={bad_activity}, "
            f"fixed_output={fixed_output!r}, bad_output={bad_output!r}"
        )
    pytest.fail("regression_test.py did not concurrently exercise compute, pass the safe implementation, and fail the raced implementation. " + " | ".join(failures))


def test_http_service_concurrency():
    inputs = [(random.uniform(1.0, 100.0), random.uniform(1.0, 100.0)) for _ in range(50)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(check_http, a, b) for a, b in inputs]
        errors = []
        for future in concurrent.futures.as_completed(futures):
            res = future.result()
            if res is not True:
                errors.append(res)
        assert not errors, f"HTTP concurrency test failed with errors: {errors[:5]}"


def test_tcp_service_concurrency():
    inputs = [(random.uniform(1.0, 100.0), random.uniform(1.0, 100.0)) for _ in range(50)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(check_tcp, a, b) for a, b in inputs]
        errors = []
        for future in concurrent.futures.as_completed(futures):
            res = future.result()
            if res is not True:
                errors.append(res)
        assert not errors, f"TCP concurrency test failed with errors: {errors[:5]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
