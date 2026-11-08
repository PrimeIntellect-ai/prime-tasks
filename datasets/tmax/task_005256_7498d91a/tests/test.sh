#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pytest

CLASSIFIER = "/home/user/classifier.py"
PLOT = "/home/user/threshold_analysis.png"


def run_classifier(path):
    try:
        return subprocess.run(
            ["python3", CLASSIFIER, path],
            capture_output=True,
            timeout=30,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Classifier timed out on {path}")


def test_classifier_exists():
    script_path = CLASSIFIER
    assert os.path.exists(script_path), f"Classifier script is missing at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"


def test_plot_exists():
    plot_path = PLOT
    assert os.path.exists(plot_path), f"Plot is missing at {plot_path}"
    assert os.path.isfile(plot_path), f"{plot_path} is not a file"

    # Require an actual, nonblank PNG rather than an empty placeholder.
    assert os.path.getsize(plot_path) > 512, "Plot file is empty or implausibly small"
    with open(plot_path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Plot is not a PNG image"
    try:
        image = np.asarray(mpimg.imread(plot_path))
    except Exception as exc:
        pytest.fail(f"Plot cannot be decoded as an image: {exc}")
    assert image.ndim in (2, 3), "Plot has invalid image dimensions"
    assert image.shape[0] > 10 and image.shape[1] > 10, "Plot is implausibly small"
    rgb = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(rgb).all(), "Plot contains invalid pixel values"
    assert float(np.max(rgb) - np.min(rgb)) > 0.20, "Plot appears blank"
    pixels = rgb.reshape(-1, rgb.shape[-1]) if rgb.ndim == 3 else rgb.reshape(-1, 1)
    sample = pixels[::max(1, len(pixels) // 10000)]
    assert len(np.unique(np.round(sample, 3), axis=0)) >= 8, "Plot lacks visible plotted content"


def test_adversarial_corpus():
    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.npy"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.npy"))

    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"

    clean_failures = []
    evil_failures = []

    # Preserve the original full-corpus assertions.
    for f in clean_files:
        if run_classifier(f) != 0:
            clean_failures.append(os.path.basename(f))

    for f in evil_files:
        if run_classifier(f) != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def generate_event(rng, is_clean):
    n = 5000
    n1 = int(n * 0.6)
    n2 = n - n1
    if is_clean:
        s1 = rng.normal(0.0, 1.0, n1)
        s2 = rng.normal(4.0, 1.5, n2)
    else:
        s1 = rng.normal(0.5, 1.2, n1)
        s2 = rng.normal(3.5, 1.3, n2)
    samples = np.concatenate((s1, s2)).astype(np.float64)
    rng.shuffle(samples)
    return samples


def test_classifier_on_fresh_neutral_path():
    # Derive fresh labeled inputs at verification time and repeatedly overwrite
    # one label-neutral path, preventing directory-name or filename classifiers.
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    labels = [0] * 12 + [1] * 12
    secrets.SystemRandom().shuffle(labels)

    with tempfile.TemporaryDirectory(prefix="telemetry_validation_") as temp_dir:
        path = os.path.join(temp_dir, "event.npy")
        failures = []
        for index, expected in enumerate(labels):
            np.save(path, generate_event(rng, is_clean=(expected == 0)))
            actual = run_classifier(path)
            if actual != expected:
                failures.append((index, expected, actual))

        assert not failures, (
            "Classifier failed fresh label-neutral telemetry inputs: "
            + ", ".join(
                f"case {i} expected {expected}, got {actual}"
                for i, expected, actual in failures
            )
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
