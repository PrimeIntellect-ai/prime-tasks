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

import h5py
import numpy as np
import pytest


def test_detector_exists():
    detector_path = "/home/user/detector.py"
    assert os.path.isfile(detector_path), f"Missing detector script at {detector_path}"


def _write_h5(path, signal):
    with h5py.File(path, "w") as f:
        f.create_dataset("rf_signal", data=signal, dtype="float64")


def _generate_signal(rng, is_evil):
    t = np.linspace(0, 1, 2000, endpoint=False)
    signal = rng.normal(0, 0.1, 2000)
    for _ in range(3):
        freq = rng.uniform(10, 100)
        phase = rng.uniform(0, 2 * np.pi)
        amp = rng.uniform(0.5, 2.0)
        signal += amp * np.sin(2 * np.pi * freq * t + phase)
    if is_evil:
        signal += 1.5 * np.sin(2 * np.pi * 450 * t)
    return signal


def test_adversarial_corpus():
    detector_path = "/home/user/detector.py"
    clean_dir = "/eval/data/clean"
    evil_dir = "/eval/data/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.h5"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.h5"))

    assert len(clean_files) > 0, f"No clean evaluation files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil evaluation files found in {evil_dir}"

    cases = []
    rng = np.random.default_rng()

    with tempfile.TemporaryDirectory(prefix="rf_inputs_") as staged_dir:
        # Re-serialize the original holdout corpus under opaque, randomized paths.
        for expected, files in ((0, clean_files), (1, evil_files)):
            for source in files:
                with h5py.File(source, "r") as f:
                    signal = np.asarray(f["rf_signal"][:], dtype=np.float64)
                staged = os.path.join(staged_dir, uuid.uuid4().hex + ".h5")
                _write_h5(staged, signal)
                cases.append((staged, expected, os.path.basename(source)))

        # Add fresh samples from the documented distribution so fixed-corpus or
        # hash-based classifiers cannot pass without analyzing the signal.
        for expected in (0, 1):
            for i in range(24):
                staged = os.path.join(staged_dir, uuid.uuid4().hex + ".h5")
                _write_h5(staged, _generate_signal(rng, expected == 1))
                cases.append((staged, expected, f"generated_{expected}_{i}.h5"))

        secrets.SystemRandom().shuffle(cases)

        failed_clean = []
        failed_evil = []
        for path, expected, display_name in cases:
            res = subprocess.run(["python3", detector_path, path], capture_output=True)
            if expected == 0 and res.returncode != 0:
                failed_clean.append(display_name)
            elif expected == 1 and res.returncode != 1:
                failed_evil.append(display_name)

    errors = []
    clean_count = len(clean_files) + 24
    evil_count = len(evil_files) + 24
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {clean_count} clean modified (rejected/failed): {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {evil_count} evil bypassed (accepted): {', '.join(failed_evil)}")

    if errors:
        pytest.fail(" | ".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
