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
import ctypes
import json
import math
import os
import re
import subprocess

import pytest
import requests

PROJECT = "/app/graph-sim-1.0"
BINARY = PROJECT + "/bin/simulate_graph"
SOURCE = PROJECT + "/src/simulator.cpp"
GRAPH = "/app/molecule_graph.dat"
REFERENCE = "/app/reference_data.csv"
URL = "http://127.0.0.1:9090/simulate"
HEADERS = {"X-API-Key": "moleculardynamics42"}


def f32(value):
    return ctypes.c_float(value).value


def independent_expected_output():
    # Independently reproduce the supplied molecular-density algorithm using
    # explicit IEEE-754 single-precision operations and a fixed accumulation
    # order. Deterministic alternatives such as sorting/Kahan summation can
    # differ slightly, so callers use a small output-formatting tolerance.
    densities = [f32(math.sin(i) * math.sin(i) * 100.0) for i in range(10000)]
    total = f32(0.0)
    three = f32(3.0)
    for density in densities:
        total = f32(total + f32(density / three))
    scale = f32(0.000001)
    correction = f32(total * scale)
    return [f32(densities[i] + correction) for i in range(10)]


def run_binary(env=None):
    result = subprocess.run(
        [BINARY, GRAPH], capture_output=True, text=True, env=env, timeout=10
    )
    assert result.returncode == 0, "Binary execution failed: " + result.stderr
    return result.stdout


def parse_values(output):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    assert len(lines) == 10, f"Expected exactly 10 density values, got {len(lines)}"
    try:
        values = [float(line) for line in lines]
    except ValueError as exc:
        pytest.fail(f"Binary emitted a non-floating-point density: {exc}")
    assert all(math.isfinite(value) for value in values), "Binary emitted a non-finite density"
    return values


def expected_api_json(values):
    mean = sum(values) / len(values)
    std = math.sqrt(sum((value - mean) ** 2 for value in values) / len(values))
    with open(REFERENCE, "r") as handle:
        ref_mean, ref_std = map(float, handle.read().strip().split(','))
    return {
        "sim_mean": round(mean, 4),
        "sim_std": round(std, 4),
        "diff_mean": round(mean - ref_mean, 4),
        "diff_std": round(std - ref_std, 4),
    }


def assert_json_matches(data, expected):
    for key in expected:
        assert key in data, f"Missing key '{key}' in JSON response"
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f"Value for {key} must be numeric"
        assert math.isclose(data[key], expected[key], abs_tol=1e-4), \
            f"Value for {key} mismatch. Expected approx {expected[key]}, got {data[key]}"


def test_source_builds_and_reduction_was_fixed():
    assert os.path.isfile(SOURCE), f"Simulator source not found at {SOURCE}"
    source = open(SOURCE, "r").read()
    # Ignore comments when checking that the active, defective OpenMP reduction
    # from the original source is no longer present.
    uncommented = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    bad_reduction = re.compile(
        r"#\s*pragma\s+omp\s+parallel\s+for[^\n]*"
        r"reduction\s*\(\s*\+\s*:\s*total\s*\)"
    )
    assert not bad_reduction.search(uncommented), \
        "The original non-deterministic OpenMP reduction is still active"

    # Rebuild from the submitted source and Makefile rather than trusting a
    # pre-existing or agent-replaced executable.
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["make", "-C", PROJECT, "all"], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"Project failed to compile with its Makefile:\n{result.stdout}\n{result.stderr}"


def test_binary_compiled_reproducible_and_matches_simulation():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"

    # Preserve the original verifier's repeated-run reproducibility assertion.
    outputs = [run_binary() for _ in range(5)]
    for index in range(1, 5):
        assert outputs[0] == outputs[index], \
            "Binary output is not deterministic across identical runs"

    # Also ensure results do not depend on the OpenMP worker count.
    thread_outputs = []
    for count in (1, 2, 3, 4):
        env = os.environ.copy()
        env["OMP_NUM_THREADS"] = str(count)
        thread_outputs.append(run_binary(env))
    assert all(output == thread_outputs[0] for output in thread_outputs[1:]), \
        "Binary output changes with the OpenMP thread count"

    actual = parse_values(outputs[0])
    oracle = independent_expected_output()
    for index, (got, expected) in enumerate(zip(actual, oracle)):
        assert math.isclose(got, expected, rel_tol=0.0, abs_tol=5e-4), \
            f"Density {index} does not match the independent simulation oracle: expected {expected}, got {got}"


def test_api_server_responses():
    # Preserve the original check that API statistics agree with the compiled
    # simulator's actual textual output.
    values = parse_values(run_binary())
    expected = expected_api_json(values)

    try:
        response = requests.post(URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("API server is not running or not reachable on 127.0.0.1:9090")
    assert response.status_code in (400, 401, 403), \
        f"Expected 4xx status code when missing API key, got {response.status_code}"

    response = requests.post(URL, headers=HEADERS, timeout=5)
    assert response.status_code == 200, \
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response text: {response.text}")
    assert_json_matches(data, expected)


def test_api_executes_binary_for_each_request():
    # Temporarily install a controlled executable at the required path. This
    # distinguishes a real API implementation from one serving cached or
    # hard-coded statistics. The compiled simulator is restored in all cases.
    backup = BINARY + ".verifier-backup"
    if os.path.exists(backup):
        os.remove(backup)
    os.replace(BINARY, backup)
    try:
        with open(BINARY, "w") as handle:
            handle.write("#!/bin/sh\nprintf '1\\n2\\n5\\n10\\n'\n")
        os.chmod(BINARY, 0o755)

        controlled_values = [1.0, 2.0, 5.0, 10.0]
        expected = expected_api_json(controlled_values)
        response = requests.post(URL, headers=HEADERS, timeout=5)
        assert response.status_code == 200, \
            f"API failed while executing the required binary: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"API did not return valid JSON. Response text: {response.text}")
        assert_json_matches(data, expected)
    finally:
        if os.path.exists(BINARY):
            os.remove(BINARY)
        os.replace(backup, BINARY)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
