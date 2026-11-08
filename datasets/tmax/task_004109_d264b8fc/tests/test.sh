#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import random
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time

import pytest
import requests

SERVER_URL = "http://127.0.0.1:8000/solve"


def stop_server(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)
    time.sleep(0.5)


def start_server(env=None):
    proc = subprocess.Popen(
        [sys.executable, "/app/server.py"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("Server process crashed during startup.")
        try:
            response = requests.post(
                SERVER_URL, json={"matrix": [[0] * 9 for _ in range(9)]}, timeout=1
            )
            if response.status_code == 200:
                return proc, response
            last_error = RuntimeError(f"startup response was HTTP {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    stop_server(proc)
    pytest.fail(f"Could not connect to the server: {last_error}")


def test_server_exists():
    assert os.path.isfile("/app/server.py"), "Expected server script at /app/server.py does not exist."


def test_c_source_bug_is_fixed_and_optimization_configured():
    solver_path = "/app/cspsolver-0.1.0/solver.c"
    setup_path = "/app/cspsolver-0.1.0/setup.py"
    assert os.path.isfile(solver_path), "solver.c is missing."
    assert os.path.isfile(setup_path), "setup.py is missing."

    solver_source = open(solver_path, encoding="utf-8").read()
    setup_source = open(setup_path, encoding="utf-8").read()

    # Reject the shipped off-by-one loop, including whitespace variations.
    assert not re.search(
        r"for\s*\([^;]*;\s*[^;]*<=\s*size\s*;", solver_source
    ), "solver.c still contains the out-of-bounds i <= size loop."
    assert re.search(
        r"for\s*\([^;]*;\s*[^;]*<\s*size\s*;", solver_source
    ), "Expected the buffer initialization loop to be bounded by i < size."

    # The task specifically requires setup.py to request standard optimization.
    assert re.search(r"-O(?:2|3|fast)\b", setup_source), (
        "setup.py does not configure a standard optimizing compiler flag such as -O2 or -O3."
    )


def test_extension_is_installed_and_handles_large_derived_inputs():
    rng = random.SystemRandom()
    matrix = [[rng.randint(-100000, 100000) for _ in range(137)] for _ in range(113)]
    code = (
        "import cspsolver, json, sys; "
        "m=json.load(sys.stdin); "
        "r=cspsolver.solve(m); "
        "print(json.dumps({'file': cspsolver.__file__, 'result': r}))"
    )
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    with tempfile.TemporaryDirectory() as cwd:
        completed = subprocess.run(
            [sys.executable, "-c", code],
            input=json.dumps(matrix),
            text=True,
            capture_output=True,
            cwd=cwd,
            env=env,
            timeout=20,
        )
    assert completed.returncode == 0, f"Installed cspsolver failed: {completed.stderr}"
    output = json.loads(completed.stdout)
    assert any(output["file"].endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"cspsolver is not an installed native extension: {output['file']}"
    )
    assert output["result"] == matrix, "cspsolver.solve returned an incorrect solution."


def test_server_really_calls_cspsolver_solve():
    # Shadow cspsolver in a fresh process with a probe implementation. A server
    # that returns a canned response instead of invoking solve cannot pass this.
    with tempfile.TemporaryDirectory() as probe_dir:
        marker = os.path.join(probe_dir, "calls.log")
        probe_source = f'''\ndef solve(matrix):
    with open({marker!r}, "a", encoding="utf-8") as f:
        f.write("called\\n")
    return [[value + 137 for value in row] for row in matrix]
'''
        with open(os.path.join(probe_dir, "cspsolver.py"), "w", encoding="utf-8") as f:
            f.write(probe_source)

        env = os.environ.copy()
        old_path = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = probe_dir + (os.pathsep + old_path if old_path else "")
        proc, _ = start_server(env)
        try:
            matrix = [[3, -8, 21], [0, 44, -19]]
            response = requests.post(SERVER_URL, json={"matrix": matrix}, timeout=3)
            assert response.status_code == 200
            assert response.json() == {
                "solution": [[value + 137 for value in row] for row in matrix]
            }, "The API did not return the result produced by cspsolver.solve."
            assert os.path.isfile(marker), "The API never called cspsolver.solve."
            assert open(marker, encoding="utf-8").read().count("called") >= 1
        finally:
            stop_server(proc)


def test_server_latency_and_correctness():
    proc, startup_response = start_server()
    try:
        zero_matrix = [[0] * 9 for _ in range(9)]
        assert startup_response.json() == {"solution": zero_matrix}

        # Exercise answers derived at verification time, not merely the fixed benchmark input.
        rng = random.SystemRandom()
        matrices = [
            [[rng.randint(-10000, 10000) for _ in range(cols)] for _ in range(rows)]
            for rows, cols in [(1, 1), (4, 7), (12, 15), (35, 28)]
        ]
        for matrix in matrices:
            response = requests.post(SERVER_URL, json={"matrix": matrix}, timeout=5)
            assert response.status_code == 200
            assert response.json() == {"solution": matrix}, "Incorrect solver response."

        # Invalid request bodies must use the documented error response shape.
        for invalid in [None, "not-a-matrix", [1, 2, 3], [[1, "x"]]]:
            response = requests.post(SERVER_URL, json={"matrix": invalid}, timeout=5)
            body = response.json()
            assert isinstance(body, dict) and isinstance(body.get("error"), str) and body["error"], (
                f"Invalid input did not produce {{'error': 'string'}}: {body}"
            )

        # Preserve the original 500-request benchmark and inspect every answer.
        latencies = []
        for i in range(500):
            try:
                response = requests.post(
                    SERVER_URL, json={"matrix": zero_matrix}, timeout=5
                )
            except requests.RequestException as exc:
                pytest.fail(
                    f"Request {i + 1}/500 failed with exception: {exc}. "
                    "The server likely crashed due to a segfault."
                )
            assert response.status_code == 200, (
                f"Request {i + 1}/500 returned status code {response.status_code}. Expected 200 OK."
            )
            assert response.json() == {"solution": zero_matrix}, (
                f"Request {i + 1}/500 returned an incorrect solution."
            )
            latencies.append(response.elapsed.total_seconds() * 1000)

        avg_latency = statistics.mean(latencies)
        assert avg_latency < 15.0, (
            f"Average latency {avg_latency:.2f}ms is not strictly below 15.0ms."
        )
    finally:
        stop_server(proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
