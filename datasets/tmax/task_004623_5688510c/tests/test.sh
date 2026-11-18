#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import subprocess
import pytest

DATASET_PATH = "/home/user/dataset.csv"
SOURCE_PATH = "/home/user/analyze.c"
RESULTS_PATH = "/home/user/results.txt"


def compute_truth():
    if not os.path.exists(DATASET_PATH):
        pytest.fail(f"Dataset missing at {DATASET_PATH}")

    data = []
    with open(DATASET_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'id': int(row['ID']),
                'a': float(row['Feature_A']),
                'b': float(row['Feature_B']),
                'c': float(row['Feature_C']),
                'target': float(row['Target'])
            })

    n = len(data)
    if n == 0:
        pytest.fail("Dataset is empty.")

    def pearson(x_key, y_key):
        sum_x = sum(d[x_key] for d in data)
        sum_y = sum(d[y_key] for d in data)
        sum_x2 = sum(d[x_key]**2 for d in data)
        sum_y2 = sum(d[y_key]**2 for d in data)
        sum_xy = sum(d[x_key]*d[y_key] for d in data)

        num = n * sum_xy - sum_x * sum_y
        den = math.sqrt((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2))
        return num / den

    cor_a = pearson('a', 'target')
    cor_b = pearson('b', 'target')
    cor_c = pearson('c', 'target')

    qA, qB, qC = 5.0, 3.0, 1.0
    for d in data:
        d['dist'] = math.sqrt((d['a']-qA)**2 + (d['b']-qB)**2 + (d['c']-qC)**2)

    sorted_data = sorted(data, key=lambda x: x['dist'])
    top3_ids = [d['id'] for d in sorted_data[:3]]

    return cor_a, cor_b, cor_c, top3_ids


def expected_output():
    cor_a, cor_b, cor_c, top3_ids = compute_truth()
    return (
        f"Correlations: Feature_A:{cor_a:.4f}, Feature_B:{cor_b:.4f}, Feature_C:{cor_c:.4f}\n"
        f"Top 3 Similar IDs: {top3_ids[0]}, {top3_ids[1]}, {top3_ids[2]}\n"
    )


def run_program(binary):
    proc = subprocess.run([binary], text=True, capture_output=True, timeout=10)
    assert proc.returncode == 0, (
        f"Compiled program exited with status {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc.stdout


def test_fixed_c_source_compiles_and_runs_correctly():
    assert os.path.isfile(SOURCE_PATH), f"C source file missing at {SOURCE_PATH}"

    binary = f"/tmp/analyze_verifier_{os.getpid()}"
    compile_proc = subprocess.run(
        ["gcc", SOURCE_PATH, "-O2", "-o", binary, "-lm"],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert compile_proc.returncode == 0, (
        f"The fixed C source did not compile.\nstdout:\n{compile_proc.stdout}"
        f"\nstderr:\n{compile_proc.stderr}"
    )

    with open(DATASET_PATH, "rb") as f:
        original_dataset = f.read()

    try:
        expected = expected_output()
        actual = run_program(binary)
        assert actual == expected, (
            f"Compiled C program output mismatch on the supplied dataset.\n"
            f"Expected:\n{expected}Found:\n{actual}"
        )

        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        rows = []
        for i in range(15):
            a = float(f"{rng.uniform(-6.0, 14.0):.12f}")
            b = float(f"{rng.uniform(-5.0, 12.0):.12f}")
            c = float(f"{rng.uniform(-4.0, 10.0):.12f}")
            target = float(f"{(1.7*a - 0.8*b + 0.45*c + rng.uniform(-1.0, 1.0)):.12f}")
            rows.append((1000 + i, a, b, c, target))

        with open(DATASET_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["ID", "Feature_A", "Feature_B", "Feature_C", "Target"])
            writer.writerows(rows)

        generated_expected = expected_output()
        generated_actual = run_program(binary)
        assert generated_actual == generated_expected, (
            f"Compiled C program output mismatch on verifier-generated data.\n"
            f"Expected:\n{generated_expected}Found:\n{generated_actual}"
        )
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_dataset)
        if os.path.exists(binary):
            os.remove(binary)


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"The output file {RESULTS_PATH} was not found. Did you run the program and redirect output?"


def test_results_content_correct():
    with open(RESULTS_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, f"The file {RESULTS_PATH} should contain at least 2 lines of output."

    cor_a, cor_b, cor_c, top3_ids = compute_truth()

    expected_line1 = f"Correlations: Feature_A:{cor_a:.4f}, Feature_B:{cor_b:.4f}, Feature_C:{cor_c:.4f}"
    expected_line2 = f"Top 3 Similar IDs: {top3_ids[0]}, {top3_ids[1]}, {top3_ids[2]}"

    assert lines[0] == expected_line1, f"Line 1 mismatch.\nExpected: '{expected_line1}'\nFound:    '{lines[0]}'"
    assert lines[1] == expected_line2, f"Line 2 mismatch.\nExpected: '{expected_line2}'\nFound:    '{lines[1]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
