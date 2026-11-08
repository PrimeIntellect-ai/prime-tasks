#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import math
import os
import re
import secrets
import stat
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/sim_project"
MAKEFILE_PATH = os.path.join(PROJECT_DIR, "Makefile")
SIMULATE_CPP_PATH = os.path.join(PROJECT_DIR, "simulate.cpp")
DIAGNOSTIC_LOG_PATH = os.path.join(PROJECT_DIR, "diagnostic.log")
OUTPUT_CSV_PATH = os.path.join(PROJECT_DIR, "output.csv")
BASELINE_CSV_PATH = os.path.join(PROJECT_DIR, "baseline.csv")
SIM_PATH = os.path.join(PROJECT_DIR, "sim")


def compute_expected_divergence():
    """Find the first divergence caused by the original float conversion."""
    val_double = 1.0
    val_buggy = 1.0

    for i in range(1, 101):
        val_double = val_double * 1.05
        temp = ctypes.c_float(val_buggy).value
        val_buggy = temp * 1.05
        if abs(val_double - val_buggy) > 0.01:
            return i

    return -1


def run_checked(command, *, env=None, timeout=30):
    result = subprocess.run(
        command,
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({' '.join(command)}):\n{result.stdout}"
    )
    return result.stdout


def read_output(path):
    assert os.path.isfile(path), f"Expected CSV was not created: {path}"
    with open(path, newline="") as handle:
        rows = list(csv.reader(handle))

    assert rows and rows[0] == ["iteration", "value"], "CSV header is incorrect."
    assert len(rows) == 101, f"Expected 100 data rows, got {len(rows) - 1}."

    parsed = []
    for expected_iteration, row in enumerate(rows[1:], 1):
        assert len(row) == 2, f"Malformed CSV row at iteration {expected_iteration}."
        assert row[0] == str(expected_iteration), (
            f"Iteration mismatch: expected {expected_iteration}, got {row[0]}"
        )
        value = float(row[1])
        assert math.isfinite(value), f"Non-finite value at iteration {expected_iteration}."
        parsed.append(value)
    return parsed


def assert_trajectory(values, multiplier):
    expected = 1.0
    for iteration, actual in enumerate(values, 1):
        expected *= multiplier
        diff = abs(actual - expected)
        assert diff < 1e-5, (
            f"Incorrect computed value at iteration {iteration}: "
            f"expected {expected}, got {actual} (diff: {diff})"
        )


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_submission():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile is missing at {MAKEFILE_PATH}"
    assert os.path.isfile(SIMULATE_CPP_PATH), f"simulate.cpp is missing at {SIMULATE_CPP_PATH}"

    run_checked(["make", "clean"])
    for stale_path in (SIM_PATH, OUTPUT_CSV_PATH):
        try:
            os.remove(stale_path)
        except FileNotFoundError:
            pass
    run_checked(["make"])

    assert os.path.isfile(SIM_PATH), "make did not create sim."
    mode = os.stat(SIM_PATH).st_mode
    assert stat.S_ISREG(mode), "sim is not a regular file."
    assert mode & stat.S_IXUSR, "sim is not executable."
    assert not mode & (stat.S_ISUID | stat.S_ISGID), "sim must not be setuid or setgid."
    with open(SIM_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "sim is not a compiled ELF executable."

    dynamic_info = run_checked(["readelf", "-d", SIM_PATH])
    needed = re.findall(r"Shared library: \[(.*?)\]", dynamic_info)
    assert "libsimmath_v2.so" in needed, "sim does not dynamically link libsimmath_v2.so."
    assert "libsimmath_v1.so" not in needed, "sim still dynamically links libsimmath_v1.so."

    # Use an unpredictable replacement implementation to prove that sim actually
    # calls compute_step_v2 and uses its double-precision result.
    factor = 1.071 + secrets.randbelow(18000) / 1_000_000.0
    with tempfile.TemporaryDirectory() as temp_dir:
        source = os.path.join(temp_dir, "probe.c")
        probe_so = os.path.join(temp_dir, "libsimmath_probe.so")
        with open(source, "w") as handle:
            handle.write(
                "double compute_step_v2(double current) { "
                f"return current * {factor:.9f}; }}\n"
            )
        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", source, "-o", probe_so],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, compile_result.stdout

        try:
            os.remove(OUTPUT_CSV_PATH)
        except FileNotFoundError:
            pass
        probe_env = os.environ.copy()
        probe_env["LD_PRELOAD"] = probe_so
        run_checked([SIM_PATH], env=probe_env)
        assert_trajectory(read_output(OUTPUT_CSV_PATH), factor)

    # Leave output.csv produced by the normal linked library for final checks.
    try:
        os.remove(OUTPUT_CSV_PATH)
    except FileNotFoundError:
        pass
    run_checked([SIM_PATH])
    assert_trajectory(read_output(OUTPUT_CSV_PATH), 1.05)


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile is missing at {MAKEFILE_PATH}"
    with open(MAKEFILE_PATH, "r") as handle:
        content = handle.read()

    assert "-lsimmath_v2" in content, "Makefile was not updated to link against libsimmath_v2."
    assert "-lsimmath_v1" not in content, "Makefile still contains the incorrect libsimmath_v1 link."


def test_simulate_cpp_fixed():
    assert os.path.isfile(SIMULATE_CPP_PATH), f"simulate.cpp is missing at {SIMULATE_CPP_PATH}"
    with open(SIMULATE_CPP_PATH, "r") as handle:
        content = handle.read()

    # Ignore comments so the supplied explanatory comment does not invalidate a fix.
    code_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.DOTALL)
    assert not re.search(r"\bfloat\b", code_without_comments), (
        "simulate.cpp still uses the float type, which causes precision loss."
    )
    assert "compute_step_v2" in content, "simulate.cpp should call compute_step_v2."


def test_diagnostic_log():
    assert os.path.isfile(DIAGNOSTIC_LOG_PATH), f"diagnostic.log is missing at {DIAGNOSTIC_LOG_PATH}"
    with open(DIAGNOSTIC_LOG_PATH, "r") as handle:
        lines = handle.read().splitlines()

    expected_iteration = compute_expected_divergence()
    expected_line1 = f"First divergence iteration: {expected_iteration}"
    expected_line2 = "Library linked: libsimmath_v2.so"

    assert any(expected_line1 in line for line in lines), (
        f"diagnostic.log does not contain the correct divergence iteration. Expected: '{expected_line1}'"
    )
    assert any(expected_line2 in line for line in lines), (
        f"diagnostic.log does not contain the correct library linked. Expected: '{expected_line2}'"
    )
    assert lines == [expected_line1, expected_line2], "diagnostic.log does not have the exact required format."


def test_output_csv_matches_baseline():
    assert os.path.isfile(OUTPUT_CSV_PATH), (
        f"output.csv is missing at {OUTPUT_CSV_PATH}. Did you run the compiled executable?"
    )
    assert os.path.isfile(BASELINE_CSV_PATH), f"baseline.csv is missing at {BASELINE_CSV_PATH}."

    with open(OUTPUT_CSV_PATH, "r") as handle:
        output_lines = handle.read().strip().split("\n")
    with open(BASELINE_CSV_PATH, "r") as handle:
        baseline_lines = handle.read().strip().split("\n")

    assert len(output_lines) == len(baseline_lines), (
        "output.csv does not have the same number of lines as baseline.csv."
    )

    for i in range(1, len(baseline_lines)):
        out_iter, out_val = output_lines[i].split(",")
        base_iter, base_val = baseline_lines[i].split(",")
        assert out_iter == base_iter, (
            f"Iteration mismatch at row {i + 1}: expected {base_iter}, got {out_iter}"
        )
        diff = abs(float(out_val) - float(base_val))
        assert diff < 1e-5, (
            f"Value mismatch at iteration {out_iter}: expected {base_val}, "
            f"got {out_val} (diff: {diff})"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
