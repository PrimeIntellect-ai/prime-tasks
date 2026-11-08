#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import glob
import secrets
import subprocess
import tempfile
import pytest
import numpy as np


def test_part1_dmd_eigenvalues():
    csv_path = '/home/user/dmd_eigenvalues.csv'
    assert os.path.isfile(csv_path), f"Missing output file: {csv_path}"

    # Recompute ground truth
    import cv2
    video_path = '/app/vibration_test.mp4'
    assert os.path.isfile(video_path), "Missing video file."

    cap = cv2.VideoCapture(video_path)
    frames = []
    for _ in range(50):
        ret, frame = cap.read()
        if not ret:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (128, 128))
        frames.append(resized.flatten())
    cap.release()

    assert len(frames) == 50, "Could not extract 50 frames from video."

    X = np.column_stack(frames)
    X1 = X[:, :-1]
    X2 = X[:, 1:]

    U, S, Vh = np.linalg.svd(X1, full_matrices=False)
    r = 5
    Ur = U[:, :r]
    Sr = S[:r]
    Vhr = Vh[:r, :]

    # A_tilde = Ur.T @ X2 @ Vhr.T @ diag(1/Sr)
    A_tilde = Ur.T @ X2 @ Vhr.T @ np.diag(1.0 / Sr)

    lambdas, _ = np.linalg.eig(A_tilde)
    omegas = np.log(lambdas) / 0.01

    # Sort by absolute magnitude descending
    sorted_indices = np.argsort(np.abs(omegas))[::-1]
    top_3_omegas = omegas[sorted_indices][:3]

    # Read CSV
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['Rank', 'Real', 'Imaginary'], "CSV header is incorrect."

        rows = list(reader)
        assert len(rows) == 3, "CSV must contain exactly 3 rows of eigenvalues."

        for i, row in enumerate(rows):
            assert int(row[0]) == i + 1, f"Rank column incorrect at row {i+1}"
            real_val = float(row[1])
            imag_val = float(row[2])

            expected_real = np.real(top_3_omegas[i])
            expected_imag = np.imag(top_3_omegas[i])

            assert np.isclose(real_val, expected_real, atol=1e-3), f"Real part mismatch at rank {i+1}: expected {expected_real}, got {real_val}"
            assert np.isclose(imag_val, expected_imag, atol=1e-3), f"Imaginary part mismatch at rank {i+1}: expected {expected_imag}, got {imag_val}"


def test_part2_matrix_filter_clean():
    script_path = '/home/user/matrix_filter.py'
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    clean_dir = '/app/corpus/clean/'
    clean_files = glob.glob(os.path.join(clean_dir, '*.npy'))
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_clean = []
    for f in clean_files:
        result = subprocess.run(['python3', script_path, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean modified (rejected instead of preserved). Offending files: {', '.join(failed_clean)}")


def test_part2_matrix_filter_evil():
    script_path = '/home/user/matrix_filter.py'
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    evil_dir = '/app/corpus/evil/'
    evil_files = glob.glob(os.path.join(evil_dir, '*.npy'))
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_evil = []
    for f in evil_files:
        result = subprocess.run(['python3', script_path, f], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(f))

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(evil_files)} evil bypassed (accepted instead of rejected). Offending files: {', '.join(failed_evil)}")


def _matrix_with_condition(rng, n, condition):
    left, _ = np.linalg.qr(rng.standard_normal((n, n)))
    right, _ = np.linalg.qr(rng.standard_normal((n, n)))
    singular_values = np.geomspace(1.0, 1.0 / condition, n)
    return left @ np.diag(singular_values) @ right.T


def test_part2_generated_content_and_arguments():
    script_path = '/home/user/matrix_filter.py'
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    # The expected outcomes are derived from newly generated matrix contents. All
    # cases use the same neutral, unpredictable path so the pathname cannot reveal
    # whether the current matrix should be accepted or rejected.
    rng = np.random.default_rng(secrets.randbits(128))
    n = int(rng.integers(6, 15))

    regular = rng.standard_normal((n, n)) + n * np.eye(n)
    moderate = _matrix_with_condition(rng, n, 1e5)
    below_limit = _matrix_with_condition(rng, n, 1e7)
    above_limit = _matrix_with_condition(rng, n, 1e10)

    singular = rng.standard_normal((n, n))
    singular[:, -1] = singular[:, 0]

    with_nan = regular.copy()
    with_nan[int(rng.integers(n)), int(rng.integers(n))] = np.nan
    with_inf = regular.copy()
    with_inf[int(rng.integers(n)), int(rng.integers(n))] = np.inf

    cases = [
        (regular, 0),
        (moderate, 0),
        (below_limit, 0),
        (above_limit, 1),
        (singular, 1),
        (with_nan, 1),
        (with_inf, 1),
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='matrix_probe_') as directory:
        matrix_path = os.path.join(directory, secrets.token_hex(12) + '.npy')
        for matrix, expected_code in cases:
            np.save(matrix_path, matrix)
            result = subprocess.run(
                ['python3', script_path, matrix_path],
                capture_output=True,
                timeout=15,
            )
            assert result.returncode == expected_code, (
                f"Generated matrix with condition {np.linalg.cond(matrix)!r} "
                f"returned {result.returncode}, expected {expected_code}. "
                f"stderr: {result.stderr.decode(errors='replace')}"
            )

        # Exactly one command-line matrix argument is required.
        missing = subprocess.run(['python3', script_path], capture_output=True, timeout=15)
        assert missing.returncode != 0, "Filter accepted an invocation with no matrix argument."

        np.save(matrix_path, regular)
        extra = subprocess.run(
            ['python3', script_path, matrix_path, matrix_path],
            capture_output=True,
            timeout=15,
        )
        assert extra.returncode != 0, "Filter accepted more than one matrix argument."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
