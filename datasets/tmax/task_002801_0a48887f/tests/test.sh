#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import ctypes
import shutil
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.stats import entropy

SIM_PATH = "/home/user/sim_expression.py"
ANALYZE_PATH = "/home/user/analyze.py"
RESULTS_PATH = "/home/user/results.json"
MARKER_PATH = f"/tmp/sim_invocations_{uuid.uuid4().hex}.log"


def expected_mesh(n):
    return [
        np.sin(i * np.pi / n) * np.cos(j * np.pi / n) + 1.0
        for i in range(n)
        for j in range(n)
    ]


def lexicographic_float32_sum(values):
    total = np.float32(0.0)
    for value in values:
        total = np.float32(total + np.float32(value))
    return float(total)


def read_output(path, n):
    with open(path, "r") as f:
        lines = [line.strip() for line in f]
    assert len(lines) == n * n + 1, f"{path} must contain one total and {n*n} grid values"
    try:
        values = [float(line) for line in lines]
    except ValueError as exc:
        pytest.fail(f"{path} contains a non-numeric line: {exc}")
    assert all(math.isfinite(v) for v in values), f"{path} contains a non-finite value"
    return values[0], values[1:]


@pytest.fixture(scope="session", autouse=True)
def execute_analysis_and_instrument_simulation():
    assert os.path.isfile(SIM_PATH), f"{SIM_PATH} does not exist or is not a regular file"
    assert os.path.isfile(ANALYZE_PATH), f"{ANALYZE_PATH} does not exist or is not a regular file"

    backup = f"/tmp/submitted_sim_{uuid.uuid4().hex}.py"
    shutil.copy2(SIM_PATH, backup)

    # The wrapper records calls made by analyze.py and applies a small, secret
    # verification-time probe to one N=64 grid value. A correct analyzer reads
    # the generated file and therefore reports the probed KL divergence rather
    # than a precomputed fixed answer.
    wrapper = '''import os
import runpy
import sys

_BACKUP = %r
_MARKER = %r
_ns = runpy.run_path(_BACKUP)
_real_run_sim = _ns["run_sim"]

def run_sim(N):
    with open(_MARKER, "a") as marker:
        marker.write(str(int(N)) + "\\n")
    result = _real_run_sim(N)
    if os.environ.get("ANALYSIS_VERIFIER_PROBE") == "1" and int(N) == 64:
        path = os.path.abspath("output_64.txt")
        with open(path, "r") as f:
            lines = f.readlines()
        # Grid coordinate (32, 0): first line is the total, hence +1.
        index = 1 + 32 * 64
        lines[index] = repr(float(lines[index].strip()) * 1.01) + "\\n"
        with open(path, "w") as f:
            f.writelines(lines)
    return result

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python sim_expression.py N")
        sys.exit(1)
    run_sim(int(sys.argv[1]))
''' % (backup, MARKER_PATH)

    try:
        with open(SIM_PATH, "w") as f:
            f.write(wrapper)

        for n in (16, 32, 64):
            try:
                os.remove(f"/home/user/output_{n}.txt")
            except FileNotFoundError:
                pass
        try:
            os.remove(RESULTS_PATH)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["ANALYSIS_VERIFIER_PROBE"] = "1"
        try:
            proc = subprocess.run(
                ["python3", ANALYZE_PATH],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=90,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("analyze.py did not finish within 90 seconds")

        assert proc.returncode == 0, (
            "Running python3 /home/user/analyze.py failed.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        yield
    finally:
        shutil.copy2(backup, SIM_PATH)
        try:
            os.remove(backup)
        except FileNotFoundError:
            pass
        try:
            os.remove(MARKER_PATH)
        except FileNotFoundError:
            pass


def test_results_json_exists():
    assert os.path.exists("/home/user/results.json"), "/home/user/results.json does not exist."


def test_analyze_script_exists():
    assert os.path.exists("/home/user/analyze.py"), "/home/user/analyze.py does not exist."


def test_output_files_exist():
    for n in [16, 32, 64]:
        assert os.path.exists(f"/home/user/output_{n}.txt"), f"/home/user/output_{n}.txt does not exist. Did analyze.py run sim_expression.py?"


def test_analyze_invoked_all_required_simulations():
    assert os.path.exists(MARKER_PATH), "analyze.py never invoked sim_expression.py"
    with open(MARKER_PATH, "r") as f:
        calls = [int(line.strip()) for line in f if line.strip()]
    for n in (16, 32, 64):
        assert n in calls, f"analyze.py did not run sim_expression.py for N={n}"


def test_generated_output_contents():
    for n in (16, 32, 64):
        total, grid = read_output(f"/home/user/output_{n}.txt", n)
        expected = expected_mesh(n)
        assert total == lexicographic_float32_sum(expected), (
            f"output_{n}.txt has the wrong lexicographical float32 total"
        )

        if n == 64:
            expected[32 * 64] *= 1.01
        assert np.allclose(grid, expected, rtol=1e-12, atol=1e-12), (
            f"output_{n}.txt does not contain the expected lexicographically flattened grid"
        )


def test_results_are_derived_from_generated_n64_output():
    with open(RESULTS_PATH, "r") as f:
        results = json.load(f)
    total, grid = read_output("/home/user/output_64.txt", 64)
    probabilities = np.asarray(grid, dtype=float)
    probabilities /= probabilities.sum()
    expected_kl = float(entropy(probabilities, np.full(64 * 64, 1.0 / (64 * 64))))

    assert math.isclose(float(results["sum_64"]), total, rel_tol=0.0, abs_tol=1e-7)
    assert math.isclose(float(results["kl_div_64"]), expected_kl, rel_tol=1e-9, abs_tol=1e-11), (
        "kl_div_64 was not calculated from the N=64 output generated during this analysis run"
    )


def test_simulation_on_unfixed_resolutions():
    seed = int.from_bytes(os.urandom(2), "big")
    candidates = [n for n in range(7, 29) if n not in (16, 32)]
    ns = [candidates[seed % len(candidates)], candidates[(seed // len(candidates) + 7) % len(candidates)]]
    if ns[1] == ns[0]:
        ns[1] = candidates[(candidates.index(ns[0]) + 1) % len(candidates)]

    for n in ns:
        expected = expected_mesh(n)
        expected_total = lexicographic_float32_sum(expected)
        with tempfile.TemporaryDirectory() as workdir:
            observed_totals = []
            for _ in range(2):
                proc = subprocess.run(
                    ["python3", SIM_PATH, str(n)],
                    cwd=workdir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert proc.returncode == 0, f"sim_expression.py failed for N={n}: {proc.stderr}"
                total, grid = read_output(os.path.join(workdir, f"output_{n}.txt"), n)
                observed_totals.append(total)
                assert total == expected_total, (
                    f"N={n} total is not a float32 accumulation in lexicographical coordinate order"
                )
                assert np.allclose(grid, expected, rtol=1e-12, atol=1e-12)
            assert observed_totals[0] == observed_totals[1], "Repeated simulation totals are not deterministic"


def test_results_values():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), "Cannot check values, results.json is missing."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON.")

    assert "sum_64" in results, "Key 'sum_64' missing in results.json"
    assert "kl_div_64" in results, "Key 'kl_div_64' missing in results.json"

    N = 64
    mesh = {}
    for i in range(N):
        for j in range(N):
            mesh[(i, j)] = math.sin(i * math.pi / N) * math.cos(j * math.pi / N) + 1.0

    sorted_keys = sorted(mesh.keys())

    total_sum = ctypes.c_float(0.0)
    for k in sorted_keys:
        val = ctypes.c_float(mesh[k])
        total_sum = ctypes.c_float(total_sum.value + val.value)

    expected_sum_64 = total_sum.value

    grid_vals = [mesh[k] for k in sorted_keys]
    sum_grid = sum(grid_vals)
    norm_grid = [v / sum_grid for v in grid_vals]

    uniform_prob = 1.0 / (N * N)
    expected_kl_div = sum(p * math.log(p / uniform_prob) for p in norm_grid if p > 0)

    assert math.isclose(results["sum_64"], expected_sum_64, rel_tol=1e-4), \
        f"sum_64 is {results['sum_64']}, expected ~{expected_sum_64}. Ensure float32 addition in lexicographical order."

    assert math.isclose(results["kl_div_64"], expected_kl_div, rel_tol=1e-4), \
        f"kl_div_64 is {results['kl_div_64']}, expected ~{expected_kl_div}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
