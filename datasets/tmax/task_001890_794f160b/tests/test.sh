#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import re
import statistics
import subprocess
import tempfile

import numpy as np
import pytest
from scipy.stats import norm

ANALYZER = "/home/user/analyze_primers.py"
TIMES = "/home/user/times.txt"
FITTER = "/home/user/fit_density.py"
RESULTS = "/home/user/profile_results.txt"


def parse_result(stdout):
    match = re.search(r"^Result:\s*([-+0-9.eE]+)\s*$", stdout, re.MULTILINE)
    assert match is not None, "analyze_primers.py did not print a numeric 'Result:'"
    return float(match.group(1))


def expected_rank3_value(x):
    c = x @ x.T
    u, s, vh = np.linalg.svd(c, full_matrices=True)
    ck = (u[:, :3] * s[:3]) @ vh[:3, :]
    return float(np.sum(ck))


def test_analyze_primers_fixed():
    path = ANALYZER
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "svd" in content.lower(), "SVD is not used in analyze_primers.py"

    # Ensure an actual SVD call is present and is not explicitly reduced.
    tree = ast.parse(content)
    svd_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if (isinstance(func, ast.Name) and func.id == "svd") or (
                isinstance(func, ast.Attribute) and func.attr == "svd"
            ):
                svd_calls.append(node)
    assert svd_calls, "analyze_primers.py does not call an SVD function"
    for call in svd_calls:
        for keyword in call.keywords:
            if keyword.arg == "full_matrices":
                assert isinstance(keyword.value, ast.Constant) and keyword.value.value is True, \
                    "SVD must be full (full_matrices=True or the default)"

    # Preserve the original fixed-batch execution assertion.
    batch_file = "/home/user/data/batch_1.txt"
    assert os.path.exists(batch_file), f"Data file {batch_file} is missing."
    result = subprocess.run(
        ["python3", path, batch_file], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"analyze_primers.py failed to run: {result.stderr}"
    assert "Result:" in result.stdout, "analyze_primers.py did not print 'Result:'"

    # Exercise the submitted program on independently generated matrices and
    # compare its output with a verifier-computed full-SVD rank-3 reconstruction.
    rng = np.random.default_rng(913742)
    matrices = [
        rng.normal(size=(7, 5)),
        rng.normal(size=(10, 4)),
    ]
    base = rng.normal(size=(8, 2))
    matrices.append(np.column_stack([base, base[:, 0], base[:, 1], base[:, 0] + base[:, 1]]))

    for x in matrices:
        fd, filename = tempfile.mkstemp(prefix="primer_matrix_", suffix=".txt")
        os.close(fd)
        try:
            np.savetxt(filename, x)
            run = subprocess.run(
                ["python3", path, filename], capture_output=True, text=True, timeout=15
            )
            assert run.returncode == 0, f"analyze_primers.py failed: {run.stderr}"
            actual = parse_result(run.stdout)
            expected = expected_rank3_value(x)
            assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-8), \
                f"Expected rank-3 SVD result {expected}, got {actual}"
        finally:
            os.unlink(filename)


def read_times():
    assert os.path.exists(TIMES), f"File {TIMES} does not exist."
    with open(TIMES, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 100, f"{TIMES} should contain exactly 100 lines, found {len(lines)}"

    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in {TIMES} is not a valid float: '{line}'")
        assert math.isfinite(value), f"Line {i+1} is not a finite execution time"
        assert value > 0, f"Line {i+1} is not a positive execution time"
        values.append(value)
    return values


def test_times_txt_and_realistic_execution_times():
    submitted = read_times()

    # Re-run every required batch and compare the recorded values with fresh real
    # wall-clock measurements. Broad tolerances allow normal scheduling noise while
    # rejecting arbitrary, zero, negative, or implausible fabricated values.
    fresh = []
    import time
    for i in range(1, 101):
        batch = f"/home/user/data/batch_{i}.txt"
        assert os.path.exists(batch), f"Data file {batch} is missing."
        start = time.perf_counter()
        run = subprocess.run(
            ["python3", ANALYZER, batch], capture_output=True, text=True, timeout=15
        )
        elapsed = time.perf_counter() - start
        assert run.returncode == 0, f"Batch {i} failed: {run.stderr}"
        assert "Result:" in run.stdout, f"Batch {i} did not produce a result"
        fresh.append(elapsed)

    for i, (recorded, measured) in enumerate(zip(submitted, fresh), 1):
        assert recorded >= 0.01, f"Recorded time for batch {i} is too small to be a real run"
        assert 0.15 * measured <= recorded <= 6.0 * measured, \
            f"Recorded time for batch {i} is implausible versus a fresh execution"

    ratio = statistics.median(submitted) / statistics.median(fresh)
    assert 0.35 <= ratio <= 3.0, \
        "The recorded timing distribution is inconsistent with real executions"


def test_fit_density_exists_and_uses_norm_fit():
    assert os.path.exists(FITTER), f"File {FITTER} does not exist."
    assert os.access(FITTER, os.X_OK), f"File {FITTER} is not executable."
    with open(FITTER, "r") as f:
        content = f.read()
    assert "scipy" in content.lower(), "fit_density.py must use scipy"
    assert re.search(r"\bnorm\s*\.\s*fit\s*\(", content), \
        "fit_density.py must call scipy.stats.norm.fit"


def test_profile_results():
    assert os.path.exists(RESULTS), f"File {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        content = f.read()

    mean_match = re.search(r"^Mean:\s*(-?\d+\.\d{4})$", content, re.MULTILINE)
    std_match = re.search(r"^Std:\s*(\d+\.\d{4})$", content, re.MULTILINE)
    assert mean_match is not None, \
        "profile_results.txt does not contain 'Mean: <value>' with 4 decimal places."
    assert std_match is not None, \
        "profile_results.txt does not contain 'Std: <value>' with 4 decimal places."

    times = read_times()
    expected_mean = statistics.mean(times)
    expected_std = statistics.pstdev(times)
    actual_mean = float(mean_match.group(1))
    actual_std = float(std_match.group(1))
    assert abs(actual_mean - expected_mean) < 1e-3, \
        f"Expected mean ~{expected_mean:.4f}, got {actual_mean}"
    assert abs(actual_std - expected_std) < 1e-3, \
        f"Expected std ~{expected_std:.4f}, got {actual_std}"


def test_fit_density_executes_on_derived_input():
    # Run the submitted fitter on verifier-controlled data so precomputed output
    # cannot satisfy the check.
    old_times = open(TIMES, "rb").read() if os.path.exists(TIMES) else None
    old_results = open(RESULTS, "rb").read() if os.path.exists(RESULTS) else None
    rng = np.random.default_rng(581239)
    values = rng.lognormal(mean=-1.7, sigma=0.35, size=37)
    expected_mean, expected_std = norm.fit(values)

    try:
        with open(TIMES, "w") as f:
            for value in values:
                f.write(f"{value:.12f}\n")
        run = subprocess.run(
            ["python3", FITTER], capture_output=True, text=True, timeout=15
        )
        assert run.returncode == 0, f"fit_density.py failed: {run.stderr}"
        assert os.path.exists(RESULTS), "fit_density.py did not create profile_results.txt"
        with open(RESULTS, "r") as f:
            output = f.read()
        match = re.fullmatch(
            r"Mean:\s*(-?\d+\.\d{4})\s*\nStd:\s*(\d+\.\d{4})\s*\n?", output
        )
        assert match is not None, "fit_density.py output is not in the required exact format"
        assert float(match.group(1)) == pytest.approx(round(float(expected_mean), 4), abs=5e-5)
        assert float(match.group(2)) == pytest.approx(round(float(expected_std), 4), abs=5e-5)
    finally:
        if old_times is None:
            if os.path.exists(TIMES):
                os.unlink(TIMES)
        else:
            with open(TIMES, "wb") as f:
                f.write(old_times)
        if old_results is None:
            if os.path.exists(RESULTS):
                os.unlink(RESULTS)
        else:
            with open(RESULTS, "wb") as f:
                f.write(old_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
