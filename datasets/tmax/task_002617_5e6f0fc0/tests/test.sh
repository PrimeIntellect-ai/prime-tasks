#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

FILTER_SCRIPT = "/home/user/filter.py"


def test_filter_script_exists():
    assert os.path.isfile(FILTER_SCRIPT), f"The script {FILTER_SCRIPT} does not exist."


def test_adversarial_corpus_evaluation():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing {FILTER_SCRIPT}"

    clean_dirs = ["/home/user/corpus/clean", "/verify/corpus/clean"]
    evil_dirs = ["/home/user/corpus/evil", "/verify/corpus/evil"]

    clean_files = []
    for d in clean_dirs:
        clean_files.extend(glob.glob(os.path.join(d, "*.bin")))

    evil_files = []
    for d in evil_dirs:
        evil_files.extend(glob.glob(os.path.join(d, "*.bin")))

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    for filepath in clean_files:
        result = subprocess.run(
            ["python3", FILTER_SCRIPT, filepath],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            clean_failed.append(os.path.basename(filepath))

    evil_failed = []
    for filepath in evil_files:
        result = subprocess.run(
            ["python3", FILTER_SCRIPT, filepath],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 1:
            evil_failed.append(os.path.basename(filepath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(clean_failed[:10])}" + ("..." if len(clean_failed) > 10 else ""))

    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(evil_failed[:10])}" + ("..." if len(evil_failed) > 10 else ""))

    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_opaque_holdout():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing {FILTER_SCRIPT}"

    rng = np.random.default_rng()
    projection = rng.standard_normal((3, 10))
    labels = np.array([0] * 20 + [1] * 20, dtype=np.int8)
    rng.shuffle(labels)
    holdout_dir = tempfile.mkdtemp(prefix="telemetry_holdout_")

    failures = []
    try:
        cases = []
        for expected in labels:
            filepath = os.path.join(holdout_dir, secrets.token_hex(16) + ".bin")
            if expected == 0:
                data = rng.standard_normal((1000, 3)) @ projection
            else:
                data = rng.standard_normal((1000, 10))
            data.astype(np.float64).tofile(filepath)
            cases.append((filepath, int(expected)))

        for filepath, expected in cases:
            result = subprocess.run(
                ["python3", FILTER_SCRIPT, filepath],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(filepath)}: expected {expected}, got {result.returncode}"
                )

        if failures:
            pytest.fail(
                f"{len(failures)} of {len(cases)} randomized holdout files misclassified. "
                + " | ".join(failures[:10])
            )
    finally:
        shutil.rmtree(holdout_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
