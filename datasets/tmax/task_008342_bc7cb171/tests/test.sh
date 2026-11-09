#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import stat
import pytest
import subprocess

RAW_DATA_PATH = "/home/user/raw_data.txt"
TSV_PATH = "/home/user/alpha_sensor.tsv"
INTEGRAL_PATH = "/home/user/integral.txt"
DERIVATIVE_PATH = "/home/user/derivative.txt"
KS_STAT_SRC = "/home/user/ks_stat.c"
KS_STAT_EXE = "/home/user/ks_stat"
REFERENCE_PATH = "/home/user/reference.txt"
KS_RESULT_PATH = "/home/user/ks_result.txt"

def parse_raw_data():
    if not os.path.exists(RAW_DATA_PATH):
        pytest.fail(f"Raw data file missing: {RAW_DATA_PATH}")

    alpha_records = []
    with open(RAW_DATA_PATH, 'r') as f:
        current_record = {}
        for line in f:
            line = line.strip()
            if line == "BEGIN_RECORD":
                current_record = {}
            elif line == "END_RECORD":
                if current_record.get("sensor") == "ALPHA":
                    alpha_records.append((float(current_record["timestamp"]), float(current_record["reading"])))
            elif ":" in line:
                key, val = line.split(":", 1)
                current_record[key.strip()] = val.strip()
    return alpha_records

def expected_ks(values1, values2):
    v1 = sorted(values1)
    v2 = sorted(values2)
    n1 = len(v1)
    n2 = len(v2)
    max_dist = 0.0
    i, j = 0, 0
    while i < n1 and j < n2:
        val = min(v1[i], v2[j])
        while i < n1 and v1[i] <= val:
            i += 1
        while j < n2 and v2[j] <= val:
            j += 1
        dist = abs((i / n1) - (j / n2))
        if dist > max_dist:
            max_dist = dist
    return max_dist

def run_ks(executable, path1, path2):
    proc = subprocess.run(
        [executable, str(path1), str(path2)],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, f"KS executable failed: {proc.stderr}"
    fields = proc.stdout.split()
    assert len(fields) == 1, f"Expected one numeric output, got: {proc.stdout!r}"
    value = float(fields[0])
    assert math.isfinite(value), f"KS executable returned a non-finite value: {value}"
    return value, proc.stdout

def test_alpha_sensor_tsv():
    assert os.path.isfile(TSV_PATH), f"File not found: {TSV_PATH}"
    expected_records = parse_raw_data()

    with open(TSV_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_records), f"Expected {len(expected_records)} rows in TSV, got {len(lines)}"

    for i, line in enumerate(lines):
        parts = line.split('\t')
        assert len(parts) == 2, f"Line {i+1} is not tab-separated into 2 columns: {line}"
        t, r = float(parts[0]), float(parts[1])
        et, er = expected_records[i]
        assert math.isclose(t, et, rel_tol=1e-5), f"Timestamp mismatch at row {i+1}: expected {et}, got {t}"
        assert math.isclose(r, er, rel_tol=1e-5), f"Reading mismatch at row {i+1}: expected {er}, got {r}"

def test_integral_txt():
    assert os.path.isfile(INTEGRAL_PATH), f"File not found: {INTEGRAL_PATH}"
    records = parse_raw_data()

    expected_integrals = [0.0]
    current_integral = 0.0
    for i in range(1, len(records)):
        t0, r0 = records[i-1]
        t1, r1 = records[i]
        area = (t1 - t0) * (r1 + r0) / 2.0
        current_integral += area
        expected_integrals.append(current_integral)

    with open(INTEGRAL_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_integrals), f"Expected {len(expected_integrals)} values in integral.txt, got {len(lines)}"

    for i, line in enumerate(lines):
        val = float(line)
        eval_ = expected_integrals[i]
        assert math.isclose(val, eval_, rel_tol=1e-5, abs_tol=1e-5), f"Integral mismatch at line {i+1}: expected {eval_}, got {val}"

def test_derivative_txt():
    assert os.path.isfile(DERIVATIVE_PATH), f"File not found: {DERIVATIVE_PATH}"
    records = parse_raw_data()

    expected_derivatives = []
    for i in range(len(records) - 1):
        t0, r0 = records[i]
        t1, r1 = records[i+1]
        diff = (r1 - r0) / (t1 - t0)
        expected_derivatives.append(diff)

    with open(DERIVATIVE_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_derivatives), f"Expected {len(expected_derivatives)} values in derivative.txt, got {len(lines)}"

    for i, line in enumerate(lines):
        val = float(line)
        eval_ = expected_derivatives[i]
        assert math.isclose(val, eval_, rel_tol=1e-5, abs_tol=1e-5), f"Derivative mismatch at line {i+1}: expected {eval_}, got {val}"

def test_ks_stat_compiled(tmp_path):
    assert os.path.isfile(KS_STAT_EXE), f"Executable not found: {KS_STAT_EXE}"
    assert os.access(KS_STAT_EXE, os.X_OK), f"File is not executable: {KS_STAT_EXE}"
    assert stat.S_ISREG(os.stat(KS_STAT_EXE).st_mode), f"Not a regular file: {KS_STAT_EXE}"
    with open(KS_STAT_EXE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "ks_stat must be a compiled native executable, not a script"

    reference_exe = tmp_path / "ks_stat_from_source"
    compile_proc = subprocess.run(
        ["gcc", KS_STAT_SRC, "-o", str(reference_exe), "-lm"],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert compile_proc.returncode == 0, f"Supplied C source does not compile with gcc: {compile_proc.stderr}"

    cases = [
        ([0.0, 1.0, 3.0, 8.0], [0.0, 0.5, 2.0, 4.0]),
        ([5.0, -2.0, 5.0, 1.5, 9.0], [4.0, 4.0, -3.0]),
        ([0.25, 0.5, 0.75], [10.0, 11.0, 12.0, 13.0]),
        ([-5.0, -1.0, 2.0, 7.0, 20.0, 21.0], [-4.0, 0.0, 0.0, 3.0, 8.0]),
    ]
    for index, (values1, values2) in enumerate(cases):
        path1 = tmp_path / f"sample_{index}_a.txt"
        path2 = tmp_path / f"sample_{index}_b.txt"
        path1.write_text("".join(f"{v}\n" for v in values1))
        path2.write_text("".join(f"{v}\n" for v in values2))

        actual, actual_stdout = run_ks(KS_STAT_EXE, path1, path2)
        reference, reference_stdout = run_ks(str(reference_exe), path1, path2)
        expected = expected_ks(values1, values2)
        assert actual_stdout == reference_stdout, "ks_stat behavior differs from the supplied C source"
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=5e-5), \
            f"Incorrect KS result for generated case {index}: expected {expected}, got {actual}"

    actual, _ = run_ks(KS_STAT_EXE, INTEGRAL_PATH, REFERENCE_PATH)
    with open(KS_RESULT_PATH, 'r') as f:
        saved = float(f.read().strip())
    assert math.isclose(saved, actual, rel_tol=1e-9, abs_tol=1e-9), \
        "ks_result.txt does not contain the output of the compiled ks_stat executable"

def test_ks_result_txt():
    assert os.path.isfile(KS_RESULT_PATH), f"File not found: {KS_RESULT_PATH}"

    # Recompute KS stat locally to verify
    records = parse_raw_data()
    expected_integrals = [0.0]
    current_integral = 0.0
    for i in range(1, len(records)):
        t0, r0 = records[i-1]
        t1, r1 = records[i]
        area = (t1 - t0) * (r1 + r0) / 2.0
        current_integral += area
        expected_integrals.append(current_integral)

    with open(REFERENCE_PATH, 'r') as f:
        ref_vals = [float(line.strip()) for line in f if line.strip()]

    v1 = sorted(expected_integrals)
    v2 = sorted(ref_vals)
    n1 = len(v1)
    n2 = len(v2)

    max_dist = 0.0
    i, j = 0, 0
    while i < n1 and j < n2:
        val = min(v1[i], v2[j])
        while i < n1 and v1[i] <= val: i += 1
        while j < n2 and v2[j] <= val: j += 1
        dist = abs((i / n1) - (j / n2))
        if dist > max_dist:
            max_dist = dist

    with open(KS_RESULT_PATH, 'r') as f:
        result = float(f.read().strip())

    assert math.isclose(result, max_dist, rel_tol=1e-3, abs_tol=1e-3), f"KS result mismatch: expected {max_dist}, got {result}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
