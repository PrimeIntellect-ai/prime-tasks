#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import inspect
import importlib.util
import subprocess
import sys

import pytest
import scipy.integrate

SCRIPT_PATH = "/home/user/generate_features.py"
CSV_PATH = "/home/user/training_features.csv"
SEQUENCES_PATH = "/home/user/sequences.txt"
EXPECTED_SEQUENCES = [
    "ATGCGTACGTAGCTAGCTAGCTAG",
    "CGATCGACTGACTAGCTAGCTAGC",
    "GGGGGGGGGGGGGGGGGGGGGGGG",
    "ATATATATATATATATATATATAT",
]


def exact_integration(seq):
    # Exact propagation over each unit interval for y' = 100*(base-y).
    decay = math.exp(-100.0)
    y = 0.0
    for base in seq:
        target = 1.0 if base in "GC" else 0.0
        y = target + (y - target) * decay
    return y


def expected_svd(seq):
    return math.sqrt(max(seq.count(base) for base in "ACGT"))


def expected_alignment(seq, primer="GCATCGATCG"):
    # localxx with zero mismatch and gap penalties has the LCS score.
    previous = [0] * (len(primer) + 1)
    for a in seq:
        current = [0]
        for j, b in enumerate(primer, 1):
            if a == b:
                current.append(previous[j - 1] + 1)
            else:
                current.append(max(previous[j], current[j - 1]))
        previous = current
    return float(previous[-1])


def load_instrumented_module():
    real_solve_ivp = scipy.integrate.solve_ivp
    signature = inspect.signature(real_solve_ivp)
    calls = []

    def recording_solve_ivp(*args, **kwargs):
        bound = signature.bind_partial(*args, **kwargs)
        bound.apply_defaults()
        calls.append({
            "t_span": tuple(bound.arguments["t_span"]),
            "method": bound.arguments["method"],
        })
        return real_solve_ivp(*args, **kwargs)

    scipy.integrate.solve_ivp = recording_solve_ivp
    try:
        spec = importlib.util.spec_from_file_location("submitted_generate_features", SCRIPT_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        probes = ["AAAA", "GGGG", "GGGAAA", "AAAGGG", "GCGCATAT"]
        values = []
        for seq in probes:
            before = len(calls)
            value = float(module.integrate_feature(seq))
            assert len(calls) == before + 1, "integrate_feature must call scipy.integrate.solve_ivp."
            call = calls[-1]
            assert call["method"] == "BDF", "integrate_feature must use solve_ivp with method='BDF'."
            assert call["t_span"] == (0, len(seq)), \
                f"Expected integration interval (0, {len(seq)}), got {call['t_span']}."
            values.append((seq, value))
        return module, values
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp


def test_script_modified():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "solve_ivp" in content, "The script does not appear to use scipy.integrate.solve_ivp as requested."
    assert "BDF" in content, "The script does not appear to use the 'BDF' method for solve_ivp."


def test_integrate_feature_executes_solve_ivp_correctly():
    _, values = load_instrumented_module()
    for seq, actual in values:
        expected = exact_integration(seq)
        assert math.isfinite(actual), f"Integration result for {seq} is not finite."
        assert abs(actual - expected) < 0.02, \
            f"Incorrect integration result for {seq}: expected about {expected}, got {actual}."


@pytest.fixture(scope="session")
def generated_csv():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.exists(SEQUENCES_PATH), f"Input file {SEQUENCES_PATH} does not exist."
    with open(SEQUENCES_PATH, "r") as f:
        sequences = [line.strip() for line in f if line.strip()]
    assert sequences == EXPECTED_SEQUENCES, "The supplied input sequences were modified or not preserved."

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"generate_features.py failed when executed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist. Did you run the script?"
    return sequences


def test_csv_output(generated_csv):
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        expected_header = ["Sequence", "Integration", "SVD", "Alignment"]
        assert header == expected_header, f"Incorrect CSV header. Expected {expected_header}, got {header}."

        rows = list(reader)
        assert len(rows) == 4, f"Expected 4 rows of data, found {len(rows)}."

        assert [row[0] for row in rows] == generated_csv, \
            "The CSV must preserve every input sequence in its original order."

        for row, expected_seq in zip(rows, generated_csv):
            assert len(row) == 4, f"Row does not have exactly 4 columns: {row}"
            seq, integration, svd, alignment = row
            assert seq == expected_seq

            try:
                int_val = float(integration)
            except ValueError:
                assert False, f"Integration value '{integration}' is not a valid float."

            assert not math.isnan(int_val), f"Integration value for sequence {seq} is NaN."
            assert not math.isinf(int_val), f"Integration value for sequence {seq} is Inf."

            try:
                svd_val = float(svd)
                alignment_val = float(alignment)
            except ValueError:
                assert False, f"SVD or Alignment values are not valid floats in row: {row}"

            expected_int = round(exact_integration(seq), 4)
            expected_svd_val = round(expected_svd(seq), 4)
            expected_alignment_val = expected_alignment(seq)
            assert abs(int_val - expected_int) <= 0.00005, \
                f"Incorrect rounded Integration value for {seq}: expected {expected_int}, got {int_val}."
            assert abs(svd_val - expected_svd_val) <= 0.00005, \
                f"Incorrect SVD value for {seq}: expected {expected_svd_val}, got {svd_val}."
            assert abs(alignment_val - expected_alignment_val) <= 1e-9, \
                f"Incorrect Alignment value for {seq}: expected {expected_alignment_val}, got {alignment_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
