#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest
from scipy import stats


def extract_latencies(video_path):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video {video_path}")

    latencies = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # OpenCV loads images in BGR format
        red_channel = frame[:, :, 2]
        latencies.append(np.mean(red_channel))
    cap.release()
    return np.array(latencies)


@pytest.fixture(scope="session")
def baseline_latencies():
    video_path = "/app/ui_test_run.mp4"
    return extract_latencies(video_path)


def test_ci_txt(baseline_latencies):
    ci_file = "/home/user/ci.txt"
    assert os.path.exists(ci_file), f"Missing {ci_file}"

    res = stats.bootstrap((baseline_latencies,), np.mean, confidence_level=0.95,
                          n_resamples=10000, method='percentile', random_state=42)
    expected_lower = round(res.confidence_interval.low, 4)
    expected_upper = round(res.confidence_interval.high, 4)

    with open(ci_file, "r") as f:
        content = f.read().strip()

    try:
        actual_lower, actual_upper = map(float, content.split(","))
    except ValueError:
        pytest.fail(f"Could not parse {ci_file}. Expected format 'lower_bound,upper_bound'")

    assert np.isclose(actual_lower, expected_lower, atol=1e-3), f"Expected lower bound ~{expected_lower}, got {actual_lower}"
    assert np.isclose(actual_upper, expected_upper, atol=1e-3), f"Expected upper bound ~{expected_upper}, got {actual_upper}"


def test_fit_txt(baseline_latencies):
    fit_file = "/home/user/fit.txt"
    assert os.path.exists(fit_file), f"Missing {fit_file}"

    expected_mean = round(np.mean(baseline_latencies), 4)
    expected_std = round(np.std(baseline_latencies, ddof=0), 4) # MLE uses ddof=0

    with open(fit_file, "r") as f:
        content = f.read().strip()

    try:
        actual_mean, actual_std = map(float, content.split(","))
    except ValueError:
        pytest.fail(f"Could not parse {fit_file}. Expected format 'mean,stddev'")

    assert np.isclose(actual_mean, expected_mean, atol=1e-3), f"Expected mean ~{expected_mean}, got {actual_mean}"
    # Allow both ddof=0 and ddof=1 just in case
    expected_std_sample = round(np.std(baseline_latencies, ddof=1), 4)
    assert np.isclose(actual_std, expected_std, atol=1e-3) or np.isclose(actual_std, expected_std_sample, atol=1e-3), \
        f"Expected stddev ~{expected_std}, got {actual_std}"


def test_adversarial_corpus():
    script_path = "/home/user/classifier.py"
    assert os.path.exists(script_path), f"Missing {script_path}"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for cf in clean_files:
        res = subprocess.run(["python3", script_path, cf], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        res = subprocess.run(["python3", script_path, ef], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed[:5])}")

    if errors:
        pytest.fail("Adversarial corpus failures:\n" + "\n".join(errors))


def test_classifier_on_unlabeled_generated_inputs(baseline_latencies):
    script_path = "/home/user/classifier.py"
    assert os.path.exists(script_path), f"Missing {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a regular file"

    rng = np.random.default_rng()
    baseline_int = np.clip(np.rint(baseline_latencies), 0, 255).astype(int)
    n = len(baseline_int)
    center = int(round(float(np.mean(baseline_latencies))))

    # These include baseline-like, shifted, resampled, and equal-center/high-spread
    # profiles. Expected statuses are always computed from the video and each
    # generated JSON array rather than inferred from a directory or label.
    balanced_spread = np.empty(n, dtype=int)
    balanced_spread[0::2] = center - int(rng.integers(14, 20))
    balanced_spread[1::2] = center + int(rng.integers(14, 20))
    rng.shuffle(balanced_spread)

    generated = [
        baseline_int.copy(),
        rng.choice(baseline_int, size=n, replace=True),
        np.clip(baseline_int + int(rng.integers(15, 26)), 0, 255),
        np.clip(balanced_spread, 0, 255),
        np.clip(np.rint(rng.normal(center, 18, n)), 0, 255).astype(int),
    ]
    rng.shuffle(generated)

    expected_statuses = [
        1 if stats.ks_2samp(trace, baseline_latencies).pvalue < 0.05 else 0
        for trace in generated
    ]
    assert 0 in expected_statuses and 1 in expected_statuses, \
        "Generated classifier tests must exercise both acceptance and rejection"

    child_env = os.environ.copy()
    child_env.pop("PYTEST_CURRENT_TEST", None)

    with tempfile.TemporaryDirectory() as input_dir:
        failures = []
        for trace, expected in zip(generated, expected_statuses):
            input_path = os.path.join(input_dir, f"{uuid.uuid4().hex}.json")
            with open(input_path, "w") as f:
                json.dump([int(value) for value in trace], f)

            result = subprocess.run(
                ["python3", script_path, input_path],
                capture_output=True,
                timeout=30,
                env=child_env,
            )
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(input_path)}: expected exit {expected}, "
                    f"got {result.returncode}"
                )

        assert not failures, "Generated-input classifier failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
