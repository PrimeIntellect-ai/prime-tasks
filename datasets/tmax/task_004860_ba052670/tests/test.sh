#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

PARAMS_PATH = "/home/user/reaction_params.json"
SOURCE_PATH = "/home/user/stability_filter.c"
EXE_PATH = "/home/user/stability_filter"
VIDEO_PATH = "/app/reaction_video.mp4"


def video_series():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    a_values, b_values = [], []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # Average a center patch to suppress codec artifacts. OpenCV uses BGR.
        a_values.append(float(np.mean(frame[40:60, 40:60, 2])))
        b_values.append(float(np.mean(frame[40:60, 140:160, 2])))
    cap.release()
    assert len(a_values) == 50, f"Expected 50 video frames, found {len(a_values)}"
    return np.asarray(a_values), np.asarray(b_values)


def fit_transitions(a, b, indices):
    dt = 0.1
    a0, b0 = a[:-1][indices], b[:-1][indices]
    da = (a[1:][indices] - a0) / dt
    db = (b[1:][indices] - b0) / dt
    design = np.vstack((np.column_stack((-a0, b0)),
                        np.column_stack((a0, -b0))))
    response = np.concatenate((da, db))
    return np.linalg.lstsq(design, response, rcond=None)[0]


def reference_estimates():
    a, b = video_series()
    n = len(a) - 1
    mean = fit_transitions(a, b, np.arange(n))
    rng = np.random.default_rng(812367)
    samples = np.empty((1000, 2))
    for i in range(1000):
        samples[i] = fit_transitions(a, b, rng.integers(0, n, n))
    lower = np.percentile(samples, 2.5, axis=0)
    upper = np.percentile(samples, 97.5, axis=0)
    return mean, lower, upper


def test_reaction_params():
    assert os.path.exists(PARAMS_PATH), f"Missing {PARAMS_PATH}"
    with open(PARAMS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PARAMS_PATH} is not valid JSON.")

    required_keys = [
        "k_mean", "k_ci_lower", "k_ci_upper",
        "c_mean", "c_ci_lower", "c_ci_upper"
    ]
    for key in required_keys:
        assert key in data, f"Missing key {key} in {PARAMS_PATH}"
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f"{key} must be numeric"
        assert math.isfinite(float(data[key])), f"{key} must be finite"

    k_mean = float(data["k_mean"])
    c_mean = float(data["c_mean"])

    # Preserve the original bounds.
    assert 0.42 <= k_mean <= 0.48, f"k_mean {k_mean} out of bounds [0.42, 0.48]"
    assert 0.12 <= c_mean <= 0.18, f"c_mean {c_mean} out of bounds [0.12, 0.18]"
    assert data["k_ci_lower"] < k_mean < data["k_ci_upper"], \
        "k_ci values are not mathematically sensible (lower < mean < upper)"
    assert data["c_ci_lower"] < c_mean < data["c_ci_upper"], \
        "c_ci values are not mathematically sensible (lower < mean < upper)"

    ref_mean, ref_lower, ref_upper = reference_estimates()
    submitted = {
        "k": (k_mean, float(data["k_ci_lower"]), float(data["k_ci_upper"])),
        "c": (c_mean, float(data["c_ci_lower"]), float(data["c_ci_upper"])),
    }
    for i, name in enumerate(("k", "c")):
        mean, lower, upper = submitted[name]
        ref_width = float(ref_upper[i] - ref_lower[i])
        assert abs(mean - float(ref_mean[i])) <= 0.035, \
            f"{name}_mean does not agree with the fit recomputed from the video"
        endpoint_tolerance = max(0.02, 2.5 * ref_width)
        assert abs(lower - float(ref_lower[i])) <= endpoint_tolerance, \
            f"{name}_ci_lower does not agree with a 1000-sample video-derived bootstrap"
        assert abs(upper - float(ref_upper[i])) <= endpoint_tolerance, \
            f"{name}_ci_upper does not agree with a 1000-sample video-derived bootstrap"
        submitted_width = upper - lower
        assert submitted_width >= max(1e-5, 0.10 * ref_width), \
            f"{name} confidence interval is implausibly narrow"
        assert submitted_width <= max(0.04, 5.0 * ref_width), \
            f"{name} confidence interval is implausibly wide"


def test_stability_filter_executable():
    assert os.path.exists(EXE_PATH), f"Missing executable {EXE_PATH}"
    assert os.path.isfile(EXE_PATH), f"{EXE_PATH} is not a regular file"
    assert os.access(EXE_PATH, os.X_OK), f"{EXE_PATH} is not executable"
    assert os.path.exists(SOURCE_PATH), f"Missing {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"


def run_filter(exe, path):
    try:
        result = subprocess.run([exe, path], capture_output=True, timeout=4)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on generated matrix {os.path.basename(path)}")
    return result.returncode


def test_stability_filter_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(clean_dir)):
        fpath = os.path.join(clean_dir, fname)
        if os.path.isfile(fpath):
            total += 1
            if run_filter(EXE_PATH, fpath) != 0:
                failed_files.append(fname)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} clean modified (rejected when they should be accepted): {', '.join(failed_files)}")


def test_stability_filter_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(evil_dir)):
        fpath = os.path.join(evil_dir, fname)
        if os.path.isfile(fpath):
            total += 1
            if run_filter(EXE_PATH, fpath) != 1:
                failed_files.append(fname)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} evil bypassed (accepted when they should be rejected): {', '.join(failed_files)}")


def simulated_status(matrix):
    x = np.ones(matrix.shape[0], dtype=np.float64)
    for _ in range(1000):
        x = x + 0.1 * matrix.dot(x)
        if np.any(np.abs(x) > 1e6):
            return 1
    return 0


def generated_matrices():
    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = np.random.default_rng(seed)
    cases = [
        np.array([[0.0]]),
        np.array([[-5.0]]),
        np.array([[-20.0]]),
        np.array([[-25.0]]),
        np.array([[2.0]]),
        np.diag(np.linspace(-19.0, -0.1, 100)),
        np.array([[-1.0, 1.0], [1.0, -1.0]]),
        np.array([[0.0, 4.0], [4.0, 0.0]]),
    ]
    for _ in range(12):
        n = int(rng.integers(2, 13))
        off = rng.uniform(0.0, 0.8, size=(n, n))
        np.fill_diagonal(off, 0.0)
        matrix = off.copy()
        for row in range(n):
            matrix[row, row] = -np.sum(matrix[row]) - rng.uniform(0.05, 2.0)
        cases.append(matrix)

        explosive = rng.uniform(-1.0, 5.0, size=(n, n))
        explosive += np.eye(n) * rng.uniform(5.0, 25.0)
        cases.append(explosive)
    return cases


def test_stability_filter_on_unseen_generated_inputs():
    with tempfile.TemporaryDirectory(prefix="matrix-check-") as directory:
        rebuilt = os.path.join(directory, "rebuilt-filter")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE_PATH, "-lm", "-o", rebuilt],
            capture_output=True, text=True
        )
        assert compile_result.returncode == 0, \
            f"stability_filter.c does not compile:\n{compile_result.stderr}"

        saw_stable = saw_unstable = False
        for matrix in generated_matrices():
            expected = simulated_status(matrix)
            saw_stable |= expected == 0
            saw_unstable |= expected == 1
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w") as f:
                f.write(f"{matrix.shape[0]}\n")
                np.savetxt(f, matrix, fmt="%.17g")
            for exe in (EXE_PATH, rebuilt):
                actual = run_filter(exe, path)
                assert actual == expected, \
                    f"{os.path.basename(exe)} returned {actual}, expected {expected}, on an unseen matrix"
        assert saw_stable and saw_unstable
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
