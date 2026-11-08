#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import shutil
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
CPP_PATH = os.path.join(HOME, "mc_integrate.cpp")
BIN_PATH = os.path.join(HOME, "mc_integrate")
OPT_PATH = os.path.join(HOME, "optimize.py")
CSV_PATH = os.path.join(HOME, "stability_results.csv")


def lcg_runif(s, min_val, max_val):
    s = (1103515245 * s + 12345) % 2147483648
    v = min_val + (max_val - min_val) * (s / 2147483648.0)
    return s, v


def simulate_cpp(k, x_min, x_max, y_min, y_max, samples, seed):
    current_seed = seed
    total_val = 0.0
    for _ in range(samples):
        current_seed, x = lcg_runif(current_seed, x_min, x_max)
        current_seed, y = lcg_runif(current_seed, y_min, y_max)
        total_val += max(0.0, math.sin(k * x) * math.cos(k * y))
    area = (x_max - x_min) * (y_max - y_min)
    return (total_val / samples) * area


def get_expected_results():
    results = {}
    for N in [2, 4, 8]:
        random.seed(42)
        k_vals = [random.uniform(1.0, 5.0) for _ in range(50)]
        best_k = None
        max_integral = -1.0
        for k in k_vals:
            total_integral = 0.0
            for i in range(N):
                for j in range(N):
                    x_min = i * math.pi / N
                    x_max = (i + 1) * math.pi / N
                    y_min = j * math.pi / N
                    y_max = (j + 1) * math.pi / N
                    total_integral += simulate_cpp(
                        k, x_min, x_max, y_min, y_max, 1000, 42
                    )
            if total_integral > max_integral:
                max_integral = total_integral
                best_k = k
        results[str(N)] = (round(best_k, 4), round(max_integral, 4))
    return results


def read_and_validate_csv(expected):
    assert os.path.exists(CSV_PATH), (
        f"The output file {CSV_PATH} is missing. The script did not generate the required output."
    )
    with open(CSV_PATH, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["N", "best_k", "max_integral"], (
            "CSV header is incorrect. Expected ['N', 'best_k', 'max_integral'], "
            f"got {header}."
        )
        rows = list(reader)

    assert len(rows) == 3, f"CSV should contain exactly 3 data rows, got {len(rows)}."
    assert [row[0] if row else None for row in rows] == ["2", "4", "8"], (
        "CSV must contain exactly one row for each N, in the required order 2, 4, 8."
    )

    for row in rows:
        assert len(row) == 3, (
            f"Each row must have exactly 3 columns, got {len(row)} in row: {row}."
        )
        n_str, k_str, int_str = row
        assert n_str in expected, f"Unexpected N value in CSV: {n_str}"
        try:
            k_val = float(k_str)
            int_val = float(int_str)
        except ValueError:
            pytest.fail(f"Could not parse numerical values in row: {row}")
        assert math.isfinite(k_val) and math.isfinite(int_val), (
            f"CSV contains a non-finite numerical value in row: {row}"
        )
        expected_k, expected_int = expected[n_str]
        assert abs(k_val - expected_k) <= 0.0002, (
            f"For N={n_str}, expected best_k ~ {expected_k}, got {k_val}."
        )
        assert abs(int_val - expected_int) <= 0.0002, (
            f"For N={n_str}, expected max_integral ~ {expected_int}, got {int_val}."
        )


def run_integrator(path, case):
    args = [path] + [str(x) for x in case]
    proc = subprocess.run(args, text=True, capture_output=True, timeout=20)
    assert proc.returncode == 0, (
        f"Integrator failed for arguments {args[1:]}: {proc.stderr}"
    )
    tokens = proc.stdout.split()
    assert len(tokens) == 1, (
        f"Integrator must print only one floating-point value, got: {proc.stdout!r}"
    )
    try:
        value = float(tokens[0])
    except ValueError:
        pytest.fail(f"Integrator output is not a floating-point number: {proc.stdout!r}")
    assert math.isfinite(value), f"Integrator returned a non-finite value: {value}"
    return value


def assert_integrator_behavior(path):
    cases = [
        (1.371, 0.0, 1.25, -0.4, 0.9, 137, 17),
        (4.613, -0.75, 2.2, 0.15, 2.75, 509, 987654321),
        (2.207, 0.31, 3.01, -1.1, -0.02, 1003, 314159),
        (3.777, -2.0, -0.2, -0.8, 1.7, 733, 42),
    ]
    for case in cases:
        actual = run_integrator(path, case)
        expected = simulate_cpp(*case)
        tolerance = max(1e-6, abs(expected) * 1e-5)
        assert abs(actual - expected) <= tolerance, (
            f"Integrator returned {actual} for {case}, expected {expected}."
        )

    valid = ["2.1", "0", "1", "0", "1", "10", "42"]
    missing = subprocess.run([path] + valid[:-1], capture_output=True, timeout=10)
    extra = subprocess.run([path] + valid + ["99"], capture_output=True, timeout=10)
    assert missing.returncode != 0, "Integrator accepted fewer than exactly 7 arguments."
    assert extra.returncode != 0, "Integrator accepted more than exactly 7 arguments."


def expected_call_arguments():
    calls = []
    for N in [2, 4, 8]:
        random.seed(42)
        k_vals = [random.uniform(1.0, 5.0) for _ in range(50)]
        for k in k_vals:
            for i in range(N):
                for j in range(N):
                    calls.append((
                        k,
                        i * math.pi / N,
                        (i + 1) * math.pi / N,
                        j * math.pi / N,
                        (j + 1) * math.pi / N,
                        1000,
                        42,
                    ))
    return calls


def test_final_state_and_pipeline():
    # Preserve the original numerical assertions and additionally reject duplicate N rows.
    original_expected = get_expected_results()
    read_and_validate_csv(original_expected)

    for path in [CPP_PATH, BIN_PATH, OPT_PATH]:
        assert os.path.exists(path), f"Required artifact is missing: {path}"
        assert os.path.isfile(path), f"Required artifact is not a regular file: {path}"

    assert os.access(BIN_PATH, os.X_OK), f"Required binary is not executable: {BIN_PATH}"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mc_integrate must be a compiled native executable."

    with open(CPP_PATH, errors="replace") as f:
        cpp_text = f.read()
    assert "mt19937" not in cpp_text, "The forbidden std::mt19937 generator is used."

    # Exercise both the submitted binary and a fresh build of the submitted C++ source.
    assert_integrator_behavior(BIN_PATH)
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "mc_integrate")
        compile_proc = subprocess.run(
            ["g++", "-O3", CPP_PATH, "-o", rebuilt],
            text=True,
            capture_output=True,
            timeout=60,
        )
        assert compile_proc.returncode == 0, (
            f"mc_integrate.cpp did not compile with the required command: {compile_proc.stderr}"
        )
        assert_integrator_behavior(rebuilt)

    # Replace the binary temporarily with a tracing test double. This verifies that
    # optimize.py performs every required subprocess call and actually consumes the
    # returned values rather than merely writing the three known CSV rows.
    backup_bin = "/tmp/mc_integrate.submitted"
    backup_csv = "/tmp/stability_results.submitted.csv"
    call_log = "/tmp/mc_integrate.calls"
    for path in [backup_bin, backup_csv, call_log]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    shutil.copy2(CSV_PATH, backup_csv)
    os.replace(BIN_PATH, backup_bin)
    try:
        wrapper = """#!/bin/sh
if [ \"$#\" -ne 7 ]; then
    exit 64
fi
printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" >> /tmp/mc_integrate.calls
printf '%s\\n' \"$1\"
"""
        with open(BIN_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(BIN_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                           stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        proc = subprocess.run(
            ["python3", OPT_PATH],
            cwd=HOME,
            text=True,
            capture_output=True,
            timeout=180,
        )
        assert proc.returncode == 0, (
            f"optimize.py failed while exercising its subprocess pipeline: {proc.stderr}"
        )

        expected_calls = expected_call_arguments()
        assert os.path.exists(call_log), "optimize.py never invoked ./mc_integrate."
        with open(call_log) as f:
            logged_calls = [line.rstrip("\n").split("\t") for line in f]
        assert len(logged_calls) == len(expected_calls), (
            f"Expected exactly {len(expected_calls)} integrator calls, got {len(logged_calls)}."
        )

        for index, (actual, expected) in enumerate(zip(logged_calls, expected_calls)):
            assert len(actual) == 7, f"Call {index} did not pass exactly 7 arguments: {actual}"
            try:
                numeric = [float(v) for v in actual[:5]]
            except ValueError:
                pytest.fail(f"Call {index} contains a non-numeric argument: {actual}")
            for pos in range(5):
                assert math.isclose(numeric[pos], expected[pos], rel_tol=0.0, abs_tol=1e-12), (
                    f"Incorrect argument {pos + 1} in integrator call {index}: "
                    f"got {actual[pos]}, expected {expected[pos]}."
                )
            assert actual[5] == "1000", f"Call {index} did not use 1000 samples."
            assert actual[6] == "42", f"Call {index} did not use seed 42."

        random.seed(42)
        max_k = max(random.uniform(1.0, 5.0) for _ in range(50))
        synthetic_expected = {
            str(N): (round(max_k, 4), round((N * N) * max_k, 4))
            for N in [2, 4, 8]
        }
        read_and_validate_csv(synthetic_expected)
    finally:
        try:
            os.unlink(BIN_PATH)
        except FileNotFoundError:
            pass
        if os.path.exists(backup_bin):
            os.replace(backup_bin, BIN_PATH)
        if os.path.exists(backup_csv):
            os.replace(backup_csv, CSV_PATH)

    # Ensure the original submitted result remains the final artifact.
    read_and_validate_csv(original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
