#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest


def compute_expected_variance(N):
    m = (N + 1) // 2
    h = 1.0 / (N + 1)
    sigma = 0.1

    sum_sq = 0.0
    for j in range(1, N + 1):
        t_inv = min(m, j) - (m * j) / (N + 1)
        sum_sq += t_inv ** 2

    v = (sigma ** 2) * (h ** 4) * sum_sq
    return f"{v:.6e}"


def validate_results_log(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    expected_Ns = [3, 9, 19, 49, 99]
    assert len(lines) == len(expected_Ns), (
        f"Expected {len(expected_Ns)} lines in results.log, found {len(lines)}"
    )

    for i, N in enumerate(expected_Ns):
        expected_var = compute_expected_variance(N)

        if N == 19:
            allowed_vars = ["1.039062e-05", "1.039063e-05"]
            pattern = rf"^N={N},\s*Var=({allowed_vars[0]}|{allowed_vars[1]})$"
            match = re.match(pattern, lines[i])
            assert match, (
                f"Line {i+1} mismatch. Expected N={N}, Var=1.039062e-05 "
                f"or 1.039063e-05, got: {lines[i]}"
            )
        else:
            expected_line = f"N={N}, Var={expected_var}"
            pattern = rf"^N={N},\s*Var={expected_var}$"
            match = re.match(pattern, lines[i])
            assert match, f"Line {i+1} mismatch. Expected {expected_line}, got: {lines[i]}"


def test_files_exist():
    assert os.path.isfile("/home/user/thermal/variance_solver.go"), "variance_solver.go is missing"
    assert os.path.isfile("/home/user/run_meshes.sh"), "run_meshes.sh is missing"
    assert os.path.isfile("/home/user/results.log"), "results.log is missing"
    assert os.path.isfile("/home/user/thermal/go.mod"), "Go module not initialized (go.mod missing)"


def test_script_executable():
    assert os.access("/home/user/run_meshes.sh", os.X_OK), "run_meshes.sh is not executable"


def test_results_log_content():
    with open("/home/user/results.log", "r") as f:
        validate_results_log(f.read())


def test_module_name():
    module_text = Path("/home/user/thermal/go.mod").read_text()
    assert re.search(r"(?m)^\s*module\s+thermal\s*$", module_text), "Go module must be named thermal"


def test_solver_builds_and_handles_arbitrary_odd_meshes():
    candidates = [n for n in range(5, 121, 2) if n not in {9, 19, 49, 99}]
    random_ns = secrets.SystemRandom().sample(candidates, 7)
    test_ns = [3, 9, 19, 49, 99] + random_ns

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "variance_solver")
        build = subprocess.run(
            ["go", "build", "-o", binary, "variance_solver.go"],
            cwd="/home/user/thermal",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert build.returncode == 0, f"variance_solver.go failed to build:\n{build.stderr}"

        output_pattern = re.compile(r"^[+-]?\d\.\d{6}e[+-]\d{2,}\n?$")
        for N in test_ns:
            run = subprocess.run(
                [binary, str(N)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert run.returncode == 0, f"Solver failed for N={N}: {run.stderr}"
            assert output_pattern.fullmatch(run.stdout), (
                f"Solver output for N={N} must contain only one scientific-notation value "
                f"with exactly 6 decimal places; got {run.stdout!r}"
            )
            got = float(run.stdout.strip())
            expected = float(compute_expected_variance(N))
            assert math.isclose(got, expected, rel_tol=6e-7, abs_tol=1e-15), (
                f"Incorrect variance for N={N}: expected approximately {expected:.6e}, got {got:.6e}"
            )


def test_run_meshes_script_actually_runs():
    log_path = Path("/home/user/results.log")
    original = log_path.read_bytes()
    try:
        log_path.write_bytes(b"")
        run = subprocess.run(
            ["/home/user/run_meshes.sh"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
        assert run.returncode == 0, f"run_meshes.sh failed:\n{run.stderr}"
        assert log_path.is_file(), "run_meshes.sh did not produce results.log"
        validate_results_log(log_path.read_text())
    finally:
        log_path.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
