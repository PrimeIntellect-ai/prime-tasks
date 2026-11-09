#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import _thread
import json
import os
import random
import subprocess
import sys
import threading
import pytest

HOME = "/home/user"
SERVICE = os.path.join(HOME, "math_service.py")
REGRESSION = os.path.join(HOME, "test_math_service.py")


def load_service():
    sys.path.insert(0, HOME)
    try:
        import math_service
        return math_service
    except ImportError:
        pytest.fail("Could not import math_service from /home/user")


def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def test_recursion_ids():
    path = "/home/user/recursion_ids.txt"
    assert os.path.isfile(path), f"{path} does not exist. You must extract the request IDs."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["1005", "1012"]
    assert lines == expected, f"Expected {path} to contain {expected}, but got {lines}."


def test_math_service_negative_n():
    math_service = load_service()

    try:
        res1 = math_service.compute_sequence(-1)
        res2 = math_service.compute_sequence(-10)
    except RecursionError:
        pytest.fail("compute_sequence still raises RecursionError for negative inputs.")

    assert res1 == -1, f"Expected compute_sequence(-1) to return -1, got {res1}."
    assert res2 == -1, f"Expected compute_sequence(-10) to return -1, got {res2}."


def test_negative_guard_is_immediate_and_positive_behavior_is_preserved():
    assert os.path.isfile(SERVICE), f"{SERVICE} does not exist."
    with open(SERVICE, "r") as f:
        tree = ast.parse(f.read(), filename=SERVICE)

    funcs = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "compute_sequence"]
    assert funcs, "compute_sequence is missing."
    body = list(funcs[0].body)
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
        body = body[1:]
    assert body and isinstance(body[0], ast.If), "compute_sequence must begin with the negative-input guard."
    guard = body[0]
    assert guard.body and isinstance(guard.body[0], ast.Return), "The negative-input guard must immediately return."
    returned = guard.body[0].value
    assert isinstance(returned, ast.UnaryOp) and isinstance(returned.op, ast.USub) and isinstance(returned.operand, ast.Constant) and returned.operand.value == 1, "The negative-input guard must return -1."

    math_service = load_service()
    rng = random.SystemRandom()
    negatives = {-rng.randint(2, 200) for _ in range(8)} | {-1}
    positives = {0, 1} | {rng.randint(2, 15) for _ in range(10)}
    for n in negatives:
        assert math_service.compute_sequence(n) == -1, f"compute_sequence({n}) must return -1."
    for n in positives:
        assert math_service.compute_sequence(n) == fib(n), f"compute_sequence({n}) no longer preserves the sequence behavior."


def test_math_service_deadlock():
    math_service = load_service()

    threads = []
    exceptions = []

    def worker(req_id, n):
        try:
            math_service.process_request(req_id, n)
        except Exception as e:
            exceptions.append(e)

    # Preserve the original concurrent even/odd regression check.
    for i in range(50):
        t = threading.Thread(target=worker, args=(i, i % 4))
        threads.append(t)
        t.start()

    for t in threads:
        t.join(timeout=2.0)
        assert not t.is_alive(), "Deadlock detected: thread hung while executing process_request."

    assert not exceptions, f"Exceptions occurred during concurrent execution: {exceptions}"


def test_locks_exist_and_are_acquired_A_then_B_for_both_branches():
    math_service = load_service()
    assert hasattr(math_service, "lock_A") and isinstance(math_service.lock_A, _thread.LockType), "lock_A must remain a threading lock."
    assert hasattr(math_service, "lock_B") and isinstance(math_service.lock_B, _thread.LockType), "lock_B must remain a threading lock."

    events = []
    held = []

    class RecordingLock:
        def __init__(self, name):
            self.name = name
        def __enter__(self):
            events.append(("acquire", self.name))
            held.append(self.name)
            return self
        def __exit__(self, exc_type, exc, tb):
            assert held and held[-1] == self.name, "Locks were not released in nested order."
            held.pop()
            events.append(("release", self.name))
            return False

    original_a, original_b = math_service.lock_A, math_service.lock_B
    try:
        math_service.lock_A = RecordingLock("A")
        math_service.lock_B = RecordingLock("B")
        rng = random.SystemRandom()
        values = [rng.randrange(2, 14, 2), rng.randrange(3, 14, 2), -rng.randrange(2, 30, 2), -rng.randrange(1, 30, 2)]
        for req_id, n in enumerate(values):
            events.clear()
            held.clear()
            result = math_service.process_request(90000 + req_id, n)
            assert events == [("acquire", "A"), ("acquire", "B"), ("release", "B"), ("release", "A")], f"process_request({n}) must acquire lock_A before lock_B; events were {events}."
            assert not held
            expected = -1 if n < 0 else fib(n)
            assert result == expected, f"process_request({n}) returned {result}, expected {expected}."
    finally:
        math_service.lock_A, math_service.lock_B = original_a, original_b


def test_randomized_concurrent_requests_complete_with_correct_results():
    math_service = load_service()
    rng = random.SystemRandom()
    values = []
    for i in range(50):
        if i % 3 == 0:
            values.append(-rng.randint(1, 40))
        elif i % 3 == 1:
            values.append(rng.randrange(0, 14, 2))
        else:
            values.append(rng.randrange(1, 14, 2))
    rng.shuffle(values)

    results = {}
    errors = []
    result_lock = threading.Lock()

    def worker(i, n):
        try:
            value = math_service.process_request(50000 + i, n)
            with result_lock:
                results[i] = value
        except BaseException as exc:
            with result_lock:
                errors.append(exc)

    threads = [threading.Thread(target=worker, args=(i, n)) for i, n in enumerate(values)]
    for thread in threads:
        thread.start()
    deadline = 4.0
    for thread in threads:
        thread.join(timeout=deadline)
        assert not thread.is_alive(), "Deadlock detected during randomized concurrent requests."
    assert not errors, f"Concurrent requests raised exceptions: {errors}"
    assert len(results) == 50
    for i, n in enumerate(values):
        expected = -1 if n < 0 else fib(n)
        assert results[i] == expected, f"process_request returned the wrong result for n={n}."


def test_regression_script():
    path = REGRESSION
    assert os.path.isfile(path), f"Regression test script {path} does not exist."

    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)
    imports_process_request = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "math_service"
        and any(alias.name == "process_request" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_process_request, "The regression script must import process_request from math_service."

    try:
        result = subprocess.run([sys.executable, path], cwd=HOME, capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {path} timed out. It may be deadlocking or taking too long.")

    assert result.returncode == 0, (
        f"Expected {path} to exit with code 0, but got {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


HARNESS = r'''
import json, os, runpy, sys, threading, time
sys.path.insert(0, "/home/user")
import math_service
mode = sys.argv[1]
state = {"calls": [], "starts": 0, "active": 0, "max_active": 0}
mu = threading.Lock()
original_start = threading.Thread.start

def checked_start(self, *a, **kw):
    with mu:
        state["starts"] += 1
    return original_start(self, *a, **kw)

threading.Thread.start = checked_start

def instrumented(req_id, n):
    with mu:
        state["calls"].append([req_id, n, threading.current_thread() is threading.main_thread()])
        call_number = len(state["calls"])
        state["active"] += 1
        state["max_active"] = max(state["max_active"], state["active"])
    try:
        if mode == "exception" and call_number == 1:
            raise RuntimeError("injected worker failure")
        time.sleep(0.03)
        return -1 if n < 0 else 0
    finally:
        with mu:
            state["active"] -= 1

math_service.process_request = instrumented
code = 0
try:
    runpy.run_path("/home/user/test_math_service.py", run_name="__main__")
except SystemExit as exc:
    code = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
except BaseException:
    code = 1
print("HARNESS_STATE=" + json.dumps(state), flush=True)
sys.exit(code)
'''


def run_instrumented_script(mode):
    harness_path = "/tmp/regression_harness.py"
    with open(harness_path, "w") as f:
        f.write(HARNESS)
    try:
        return subprocess.run([sys.executable, harness_path, mode], cwd=HOME, capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Regression script timed out in {mode} instrumentation mode.")


def test_regression_script_really_launches_50_mixed_concurrent_workers():
    result = run_instrumented_script("good")
    assert result.returncode == 0, f"Regression script failed with a successful process_request implementation.\n{result.stdout}\n{result.stderr}"
    marker = [line for line in result.stdout.splitlines() if line.startswith("HARNESS_STATE=")]
    assert marker, "Could not observe the regression script's worker activity."
    state = json.loads(marker[-1].split("=", 1)[1])
    calls = state["calls"]
    assert state["starts"] >= 50, f"Regression script started only {state['starts']} threads; at least 50 are required."
    assert len(calls) >= 50, f"Regression script made only {len(calls)} process_request calls; at least 50 are required."
    assert all(not call[2] for call in calls), "process_request must be invoked by worker threads, not the main thread."
    values = [call[1] for call in calls]
    assert any(isinstance(n, int) and n < 0 for n in values), "Regression inputs must include negative integers."
    assert any(isinstance(n, int) and n >= 0 and n % 2 == 0 for n in values), "Regression inputs must include even integers."
    assert any(isinstance(n, int) and n >= 0 and n % 2 == 1 for n in values), "Regression inputs must include odd integers."
    assert state["max_active"] >= 2, "Regression workers were not run concurrently."


def test_regression_script_detects_worker_exceptions():
    result = run_instrumented_script("exception")
    assert result.returncode != 0, "Regression script exited successfully even though a worker threw an exception."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
