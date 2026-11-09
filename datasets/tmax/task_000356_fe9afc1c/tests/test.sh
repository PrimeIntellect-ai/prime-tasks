#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile
import uuid

import matplotlib.image as mpimg
import numpy as np
import pytest
from scipy.io import wavfile


def test_psd_image_exists():
    """Check that the PSD image was generated and is a valid, nonempty PNG plot."""
    path = "/home/user/psd.png"
    assert os.path.isfile(path), f"Missing PSD image file: {path}"

    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "psd.png is not a PNG file"

    try:
        image = mpimg.imread(path)
    except Exception as exc:
        pytest.fail(f"psd.png is not a readable image: {exc}")

    assert image.ndim in (2, 3), "psd.png has an invalid image shape"
    assert image.shape[0] >= 200 and image.shape[1] >= 200, "psd.png is too small to be a usable plot"
    assert np.isfinite(image).all(), "psd.png contains invalid pixel values"
    assert float(np.std(image)) > 0.01, "psd.png appears blank or uniform"


def test_classifier_exists_and_executable():
    """Check that the classifier exists and is executable."""
    path = "/home/user/classifier"
    assert os.path.isfile(path), f"Missing classifier executable: {path}"
    assert os.access(path, os.X_OK), f"Classifier is not executable: {path}"


def classify_files(classifier_path, labeled_files):
    failures = []
    for path, expected in labeled_files:
        try:
            result = subprocess.run(
                [classifier_path, path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            failures.append((os.path.basename(path), expected, "timeout"))
            continue
        if result.returncode != expected:
            failures.append((os.path.basename(path), expected, result.returncode))
    return failures


def test_classifier_on_adversarial_corpus():
    """Keep the original held-out corpus check."""
    classifier_path = "/home/user/classifier"
    clean_dir = "/app/verifier/clean"
    evil_dir = "/app/verifier/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.wav"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.wav"))

    assert len(clean_files) > 0, "No clean files found in verifier corpus."
    assert len(evil_files) > 0, "No evil files found in verifier corpus."

    failed_clean = []
    for f in clean_files:
        result = subprocess.run([classifier_path, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        result = subprocess.run([classifier_path, f], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(f))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files incorrectly classified as evil (exit code != 0): {failed_clean[:5]}...")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed classification (exit code != 1): {failed_evil[:5]}...")

    if errors:
        pytest.fail("\n".join(errors))


def test_classifier_on_fresh_neutral_paths():
    """Generate fresh audio under label-free random paths so path inspection cannot pass."""
    classifier_path = "/home/user/classifier"
    sr = 44100
    duration = 3.0
    sample_count = int(sr * duration)
    t = np.arange(sample_count, dtype=np.float64) / sr
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "big"))

    with tempfile.TemporaryDirectory(prefix="acoustic_eval_") as workdir:
        cases = []
        labels = [0] * 8 + [1] * 8
        rng.shuffle(labels)

        for expected in labels:
            signal = rng.normal(0.0, 0.5, size=sample_count)
            if expected == 1:
                amplitude = rng.uniform(0.5, 1.5)
                phase = rng.uniform(0.0, 2.0 * np.pi)
                signal += amplitude * np.sin(2.0 * np.pi * 4410.0 * t + phase)

            signal = np.clip(signal / np.max(np.abs(signal)), -1.0, 1.0)
            pcm = np.int16(signal * 32767)
            path = os.path.join(workdir, uuid.uuid4().hex + ".wav")
            wavfile.write(path, sr, pcm)
            cases.append((path, expected))

        rng.shuffle(cases)
        failures = classify_files(classifier_path, cases)
        assert not failures, f"Classifier failed fresh label-free audio cases: {failures[:5]}"


def test_threshold_optimization_script():
    """Require and execute a separate script that derives the spectral threshold."""
    classifier_realpath = os.path.realpath("/home/user/classifier")
    candidates = []

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) == classifier_realpath or path == "/home/user/psd.png":
                continue
            try:
                with open(path, "rb") as f:
                    raw = f.read(1024 * 1024 + 1)
            except OSError:
                continue
            if len(raw) > 1024 * 1024 or b"\x00" in raw:
                continue
            try:
                source = raw.decode("utf-8").lower()
            except UnicodeDecodeError:
                continue

            is_script = name.endswith((".py", ".sh")) or source.startswith("#!")
            has_inputs = "corpus" in source and "clean" in source and "evil" in source
            has_method = "threshold" in source and any(
                token in source for token in ("fft", "rfft", "periodogram", "welch", "spectral", "frequency")
            )
            if is_script and has_inputs and has_method:
                candidates.append(path)

    assert candidates, "Missing a separate threshold-optimization script using the clean and evil spectral data"

    attempts = []
    argument_sets = [
        [],
        ["/app/corpus/clean", "/app/corpus/evil"],
        ["/app/reference_signal.wav", "/app/corpus/clean", "/app/corpus/evil"],
    ]
    for path in candidates:
        if path.endswith(".py"):
            launcher = ["python3", path]
        elif path.endswith(".sh"):
            launcher = ["bash", path]
        elif os.access(path, os.X_OK):
            launcher = [path]
        else:
            continue

        for args in argument_sets:
            try:
                result = subprocess.run(
                    launcher + args,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                    cwd="/home/user",
                )
            except subprocess.TimeoutExpired:
                attempts.append(f"{path} {args}: timeout")
                continue
            if result.returncode == 0:
                return
            attempts.append(f"{path} {args}: exit {result.returncode}")

    pytest.fail("Threshold-optimization script could not be executed successfully: " + "; ".join(attempts[:6]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
