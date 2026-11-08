#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import stat
import subprocess

SCRIPT = "/home/user/filter_outliers.sh"
EMBEDDINGS = "/home/user/embeddings.csv"
THRESHOLDS = ["0.5", "1.0", "1.5", "2.0", "2.5", "3.0"]


def run_filter(threshold):
    result = subprocess.run(
        [SCRIPT, str(threshold)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Script failed for threshold {threshold}. Stderr: {result.stderr}"
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def expected_ids(path, threshold):
    expected = set()
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            norm = math.sqrt(sum(float(row[f"v{i}"]) ** 2 for i in range(1, 6)))
            if norm < float(threshold):
                expected.add(row["ID"])
    return expected


def test_best_threshold():
    path = "/home/user/best_threshold.txt"
    assert os.path.exists(path), f"File {path} is missing. Did you write the best threshold to this file?"
    with open(path, "r") as f:
        val = f.read().strip()
    assert val == "2.5", f"Expected best threshold to be 2.5, but got '{val}' in {path}."


def test_cleaned_dataset():
    path = "/home/user/cleaned_dataset.csv"
    assert os.path.exists(path), f"File {path} is missing. Did you save the cleaned dataset?"
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids_set = {'E01', 'E02', 'E03', 'E05', 'E07', 'E08', 'E10', 'E11', 'E13'}
    actual_ids = set(lines)

    missing = expected_ids_set - actual_ids
    extra = actual_ids - expected_ids_set

    error_msg = f"Cleaned dataset IDs in {path} do not match the expected output."
    if missing:
        error_msg += f" Missing expected IDs: {missing}."
    if extra:
        error_msg += f" Found unexpected IDs: {extra}."

    assert actual_ids == expected_ids_set, error_msg


def test_filter_outliers_script_fixed():
    path = SCRIPT
    assert os.path.exists(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    result = subprocess.run([path, "2.5"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute properly. Stderr: {result.stderr}"

    output_ids = set(result.stdout.strip().split('\n'))
    output_ids = {x for x in output_ids if x}

    expected = {'E01', 'E02', 'E03', 'E05', 'E07', 'E08', 'E10', 'E11', 'E13'}
    missing = expected - output_ids
    extra = output_ids - expected

    error_msg = "The script filter_outliers.sh did not output the correct IDs for threshold 2.5. Is the locale/decimal bug fully fixed?"
    if missing:
        error_msg += f" Missing IDs: {missing}."
    if extra:
        error_msg += f" Unexpected IDs: {extra}."

    assert output_ids == expected, error_msg


def test_filter_outliers_all_tuning_thresholds():
    for threshold in THRESHOLDS:
        actual = run_filter(threshold)
        expected = expected_ids(EMBEDDINGS, threshold)
        assert actual == expected, (
            f"Incorrect IDs for threshold {threshold}: "
            f"missing {expected - actual}, unexpected {actual - expected}"
        )


def test_filter_outliers_uses_current_embedding_values():
    original = open(EMBEDDINGS, "rb").read()
    original_mode = stat.S_IMODE(os.stat(EMBEDDINGS).st_mode)
    replacement = """ID,v1,v2,v3,v4,v5
T_A,0.10,0.00,0.00,0.00,0.00
T_B,0.30,0.40,0.00,0.00,0.00
T_C,-0.60,0.80,0.00,0.00,0.00
T_D,0.90,0.90,0.90,0.00,0.00
T_E,1.20,1.60,0.00,0.00,0.00
T_F,1.50,2.00,0.00,0.00,0.00
T_G,3.00,0.00,0.00,0.00,0.00
T_H,0.70,0.70,0.70,0.70,0.70
T_I,-1.01,0.02,0.03,0.04,0.05
"""

    try:
        with open(EMBEDDINGS, "w", newline="") as f:
            f.write(replacement)

        for threshold in THRESHOLDS:
            actual = run_filter(threshold)
            expected = expected_ids(EMBEDDINGS, threshold)
            assert actual == expected, (
                f"The script did not parse and calculate the replacement data "
                f"correctly at threshold {threshold}: missing {expected - actual}, "
                f"unexpected {actual - expected}"
            )
    finally:
        with open(EMBEDDINGS, "wb") as f:
            f.write(original)
        os.chmod(EMBEDDINGS, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
