#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/sanitiser.py"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
OUTPUT_FILE = "/tmp/output.json"
THRESHOLD = 8500.0


def run_sanitiser(input_dir, output_file):
    assert os.path.isfile(SCRIPT_PATH), f"Sanitiser script not found at {SCRIPT_PATH}"
    cmd = ["python3", SCRIPT_PATH, "--input_dir", input_dir, "--output_file", output_file]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(output_file), f"Output JSON file not created at {output_file}"

    with open(output_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_file} is not valid JSON.")

    os.remove(output_file)
    return data


def test_clean_corpus_classification():
    """Test that all files in the clean corpus are classified as 'clean'."""
    clean_files = [os.path.basename(f) for f in glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.npy"))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    output_data = run_sanitiser(CLEAN_CORPUS_DIR, OUTPUT_FILE)

    failed_files = []
    for f in clean_files:
        if f not in output_data:
            failed_files.append(f"{f} (missing)")
        elif output_data[f] != "clean":
            failed_files.append(f"{f} (classified as {output_data[f]})")

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: "
            + ", ".join(failed_files)
        )


def test_evil_corpus_classification():
    """Test that all files in the evil corpus are classified as 'evil'."""
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.npy"))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    output_data = run_sanitiser(EVIL_CORPUS_DIR, OUTPUT_FILE)

    failed_files = []
    for f in evil_files:
        if f not in output_data:
            failed_files.append(f"{f} (missing)")
        elif output_data[f] != "evil":
            failed_files.append(f"{f} (classified as {output_data[f]})")

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil files bypassed: "
            + ", ".join(failed_files)
        )


def _matrix_with_condition_number(rng, condition_number, size):
    left, _ = np.linalg.qr(rng.normal(size=(size, size)))
    right, _ = np.linalg.qr(rng.normal(size=(size, size)))
    singular_values = np.geomspace(condition_number, 1.0, size)
    return left @ np.diag(singular_values) @ right.T


def test_mixed_fresh_matrices_are_classified_by_l2_condition_number():
    """Exercise both labels in one fresh directory using computed condition numbers."""
    rng = np.random.default_rng()

    matrices = [
        _matrix_with_condition_number(rng, 2.0, 3),
        _matrix_with_condition_number(rng, 8499.0, 4),
        np.diag([8500.0, 1.0]),
        _matrix_with_condition_number(rng, 8501.0, 5),
        _matrix_with_condition_number(rng, 25000.0, 3),
        np.array([[1.0, 2.0], [2.0, 4.0]]),
    ]
    rng.shuffle(matrices)

    with tempfile.TemporaryDirectory(prefix="matrix_inbox_") as input_dir:
        expected = {}
        for matrix in matrices:
            filename = f"sample_{secrets.token_hex(10)}.npy"
            np.save(os.path.join(input_dir, filename), matrix)
            condition_number = np.linalg.cond(matrix, p=2)
            expected[filename] = "clean" if condition_number < THRESHOLD else "evil"

        labels = set(expected.values())
        assert labels == {"clean", "evil"}, "Generated test data did not cover both classifications"

        output_file = os.path.join(input_dir, "result.json")
        actual = run_sanitiser(input_dir, output_file)

        assert isinstance(actual, dict), "Output JSON must be a dictionary"
        assert set(actual.keys()) == set(expected.keys()), (
            "Output must contain exactly one entry for each .npy base filename"
        )
        assert actual == expected, (
            "Fresh matrices were not classified according to their L2 condition numbers "
            "and the voicemail threshold"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
