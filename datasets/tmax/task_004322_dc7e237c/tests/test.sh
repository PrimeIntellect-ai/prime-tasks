#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

EVIL_DIR = "/app/corpus/evil"
CLEAN_DIR = "/app/corpus/clean"
VIDEO_PATH = "/app/sensor_feed.mp4"
SANITIZER_PATH = "/home/user/sanitizer"
COUNT_FILE = "/home/user/clean_frame_count.txt"


def run_sanitizer(path):
    try:
        return subprocess.run(
            [SANITIZER_PATH, path], capture_output=True, timeout=20
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out on {path}")


def write_matrix(path, matrix):
    matrix = np.asarray(matrix, dtype=np.float64)
    assert matrix.ndim == 2 and matrix.shape[0] == matrix.shape[1]
    with open(path, "w") as f:
        f.write(f"{matrix.shape[0]}\n")
        for row in matrix:
            f.write(" ".join(format(float(x), ".17g") for x in row) + "\n")


def test_sanitizer_exists_and_executable():
    """Ensure the sanitizer is an executable native program using OpenMP."""
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer not found at {SANITIZER_PATH}"
    assert os.access(SANITIZER_PATH, os.X_OK), f"Sanitizer at {SANITIZER_PATH} is not executable"

    with open(SANITIZER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled native executable"

    symbols = subprocess.run(
        ["readelf", "-Ws", SANITIZER_PATH], capture_output=True, text=True
    )
    dynamic = subprocess.run(
        ["readelf", "-d", SANITIZER_PATH], capture_output=True, text=True
    )
    assert symbols.returncode == 0 and dynamic.returncode == 0, "Unable to inspect sanitizer executable"
    omp_evidence = symbols.stdout + symbols.stderr + dynamic.stdout + dynamic.stderr
    assert re.search(r"libgomp|GOMP_|\bomp_", omp_evidence), \
        "Sanitizer executable does not contain evidence of OpenMP use"


def test_sanitizer_on_corpus():
    """Retain the original checks against the supplied adversarial corpus."""
    if not os.path.isfile(SANITIZER_PATH):
        pytest.fail(f"Sanitizer not found at {SANITIZER_PATH}")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR)
                  if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR)
                   if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_DIR}"
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_DIR}"

    evil_bypassed = []
    clean_modified = []

    for e_file in evil_files:
        if run_sanitizer(e_file) == 0:
            evil_bypassed.append(os.path.basename(e_file))

    for c_file in clean_files:
        if run_sanitizer(c_file) != 0:
            clean_modified.append(os.path.basename(c_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:10])}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:10])}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_on_generated_unlabelled_matrices():
    """Exercise novel matrices at neutral, unpredictable paths."""
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
    cases = []

    for n in (11, 29, 100):
        q, _ = np.linalg.qr(rng.standard_normal((n, n)))
        clean = q @ np.diag(rng.uniform(1.0, 3.0, n)) @ q.T
        cases.append((clean, 0))

        x = rng.standard_normal((n, n))
        clean_gram = x @ x.T + np.eye(n) * n
        cases.append((clean_gram, 0))

        q, _ = np.linalg.qr(rng.standard_normal((n, n)))
        tiny_spectrum = np.geomspace(1.0, 1e-16, n)
        ill_conditioned = q @ np.diag(tiny_spectrum) @ q.T
        cases.append((ill_conditioned, 1))

        x = rng.standard_normal((n, n - 1))
        rank_deficient = x @ x.T
        cases.append((rank_deficient, 1))

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="matrix_checks_" + uuid.uuid4().hex + "_") as directory:
        failures = []
        for matrix, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".txt")
            write_matrix(path, matrix)
            actual = run_sanitizer(path)
            if actual != expected:
                failures.append((matrix.shape[0], expected, actual))
        assert not failures, f"Sanitizer misclassified generated matrices: {failures}"


def test_clean_frame_count():
    """Derive the video result by decoding every frame and invoking the sanitizer."""
    assert os.path.isfile(COUNT_FILE), f"Count file not found at {COUNT_FILE}"
    with open(COUNT_FILE, "r") as f:
        content = f.read().strip()

    try:
        count = int(content)
    except ValueError:
        pytest.fail(f"Content of {COUNT_FILE} is not a valid integer: '{content}'")

    # Preserve the original expected-result assertion.
    assert count == 45, f"Expected 45 clean frames, but found {count}"

    capture = cv2.VideoCapture(VIDEO_PATH)
    assert capture.isOpened(), f"Could not open video {VIDEO_PATH}"
    derived_count = 0
    frame_count = 0

    try:
        with tempfile.TemporaryDirectory(prefix="frame_checks_" + uuid.uuid4().hex + "_") as directory:
            while True:
                ok, frame = capture.read()
                if not ok:
                    break
                if frame.ndim == 3:
                    frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                assert frame.shape == (100, 100), f"Unexpected frame shape: {frame.shape}"

                matrix = frame.astype(np.float64) / 255.0
                path = os.path.join(directory, uuid.uuid4().hex + ".txt")
                write_matrix(path, matrix)
                if run_sanitizer(path) == 0:
                    derived_count += 1
                frame_count += 1
    finally:
        capture.release()

    assert frame_count > 0, "No frames were decoded from the sensor video"
    assert derived_count == count, \
        f"Stored clean-frame count {count} does not match sanitizer result {derived_count}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
