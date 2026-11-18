#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pytest
from scipy.io import wavfile

SCRIPT_PATH = "/home/user/detect_divergence.sh"
CLEAN_DIR = "/app/data/clean"
EVIL_DIR = "/app/data/evil"


def test_script_exists_and_executable():
    """Check that the detect_divergence.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    """Test the script against the clean and evil corpora."""
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.wav"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.wav"))

    assert len(clean_files) > 0, "No clean files found for testing."
    assert len(evil_files) > 0, "No evil files found for testing."

    clean_failed = []
    for cf in clean_files:
        try:
            result = subprocess.run([SCRIPT_PATH, cf], capture_output=True, text=True, timeout=10)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_failed.append((os.path.basename(cf), output))
        except Exception as e:
            clean_failed.append((os.path.basename(cf), str(e)))

    evil_failed = []
    for ef in evil_files:
        try:
            result = subprocess.run([SCRIPT_PATH, ef], capture_output=True, text=True, timeout=10)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_failed.append((os.path.basename(ef), output))
        except Exception as e:
            evil_failed.append((os.path.basename(ef), str(e)))

    error_messages = []
    if clean_failed:
        failed_names = [name for name, _ in clean_failed]
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (incorrectly classified). Offending files: {', '.join(failed_names)}")

    if evil_failed:
        failed_names = [name for name, _ in evil_failed]
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (incorrectly classified). Offending files: {', '.join(failed_names)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def expected_classification(samples):
    consecutive = 0
    for sample in samples:
        if abs(float(sample)) > 0.98:
            consecutive += 1
            if consecutive > 5:
                return "EVIL"
        else:
            consecutive = 0
    return "CLEAN"


def test_generated_unseen_files_at_unlabeled_paths():
    """Exercise the threshold rule on newly generated files whose paths reveal no label."""
    rng = np.random.default_rng(secrets.randbits(128))

    with tempfile.TemporaryDirectory(prefix="wavcheck_" + secrets.token_hex(8) + "_") as tmpdir:
        cases = []

        # Randomized boundary cases: five over-threshold samples remain valid,
        # while six or more consecutive samples are divergent.
        for run_length in range(0, 11):
            samples = rng.uniform(-0.70, 0.70, 16000).astype(np.float32)
            if run_length:
                start = int(rng.integers(100, len(samples) - run_length - 100))
                magnitude = float(rng.uniform(0.985, 0.999))
                sign = -1.0 if rng.integers(0, 2) else 1.0
                samples[start:start + run_length] = sign * magnitude
            cases.append(samples)

        # High samples interrupted before reaching six must not be combined.
        for _ in range(5):
            samples = rng.uniform(-0.75, 0.75, 16000).astype(np.float32)
            start = int(rng.integers(100, len(samples) - 200))
            samples[start:start + 3] = 0.995
            samples[start + 3] = 0.0
            samples[start + 4:start + 9] = -0.995
            cases.append(samples)

        # Add divergent runs at unpredictable positions and with either polarity.
        for _ in range(9):
            samples = rng.uniform(-0.80, 0.80, 16000).astype(np.float32)
            run_length = int(rng.integers(6, 20))
            start = int(rng.integers(100, len(samples) - run_length - 100))
            samples[start:start + run_length] = rng.choice([-0.99, 0.99])
            cases.append(samples)

        rng.shuffle(cases)
        failures = []
        for samples in cases:
            filename = secrets.token_hex(16) + ".wav"
            path = os.path.abspath(os.path.join(tmpdir, filename))
            wavfile.write(path, 16000, samples)

            # Derive the answer from the actual samples read back from the file.
            _, decoded = wavfile.read(path)
            expected = expected_classification(decoded)
            try:
                result = subprocess.run(
                    [SCRIPT_PATH, path], capture_output=True, text=True, timeout=10
                )
                actual = result.stdout.strip()
                if result.returncode != 0 or actual != expected:
                    failures.append(
                        f"{filename}: expected {expected}, got {actual!r}, exit={result.returncode}"
                    )
            except Exception as exc:
                failures.append(f"{filename}: {exc}")

        assert not failures, "Generated unseen-file failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
