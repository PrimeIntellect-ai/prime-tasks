#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import secrets
import shutil
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.io import wavfile


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector"
    assert os.path.isfile(detector_path), f"Detector executable not found at {detector_path}"
    assert os.access(detector_path, os.X_OK), f"Detector at {detector_path} is not executable"


def test_adversarial_corpus():
    detector_path = "/home/user/detector"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.wav"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.wav"))

    assert len(clean_files) > 0, f"No files found in {clean_dir}"
    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    clean_failed = []
    for f in clean_files:
        result = subprocess.run([detector_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        result = subprocess.run([detector_path, f], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(f))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")

    assert not error_messages, "\n".join(error_messages)


def _generate_wav(path, is_evil, rng):
    sample_rate = 44100
    duration = 2.0
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    signal = rng.standard_normal(len(t)) * 0.5

    if is_evil:
        signal += 0.05 * np.sin(2 * np.pi * 14500 * t)

    signal = np.int16(signal / np.max(np.abs(signal)) * 32767)
    wavfile.write(path, sample_rate, signal)


def test_fresh_hidden_corpus_on_neutral_paths():
    detector_path = "/home/user/detector"
    corpus_dir = tempfile.mkdtemp(prefix="wavcheck_")
    try:
        rng = np.random.default_rng(secrets.randbits(128))
        labels = [0] * 8 + [1] * 8
        secrets.SystemRandom().shuffle(labels)

        cases = []
        for expected in labels:
            path = os.path.join(corpus_dir, f"{uuid.uuid4().hex}.wav")
            _generate_wav(path, expected == 1, rng)
            cases.append((path, expected))

        failures = []
        for path, expected in cases:
            result = subprocess.run([detector_path, path], capture_output=True)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} returned {result.returncode}, expected {expected}"
                )

        assert not failures, "Fresh hidden corpus failures:\n" + "\n".join(failures)
    finally:
        shutil.rmtree(corpus_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
