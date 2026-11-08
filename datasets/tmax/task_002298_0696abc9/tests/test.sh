#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import h5py
import numpy as np
import pytest


def test_detector_exists():
    detector_path = "/home/user/detector.py"
    assert os.path.exists(detector_path), f"Expected detector script at {detector_path} does not exist."
    assert os.path.isfile(detector_path), f"{detector_path} is not a file."


def test_detector_on_mixed_corpus():
    detector_path = "/home/user/detector.py"
    clean_dir = "/app/hidden_corpus/clean/"
    evil_dir = "/app/hidden_corpus/evil/"

    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} does not exist."
    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} does not exist."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.h5')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.h5')]
    assert len(clean_files) > 0, f"No HDF5 files found in clean corpus {clean_dir}."
    assert len(evil_files) > 0, f"No HDF5 files found in evil corpus {evil_dir}."

    cases = []
    for fpath in clean_files:
        with h5py.File(fpath, 'r') as f:
            cases.append((np.asarray(f['/sensor_data']), 0, os.path.basename(fpath)))
    for fpath in evil_files:
        with h5py.File(fpath, 'r') as f:
            cases.append((np.asarray(f['/sensor_data']), 1, os.path.basename(fpath)))

    # Add freshly generated held-out samples so fixed hashes or names cannot act as labels.
    rng = np.random.default_rng()
    fresh_labels = [0] * 20 + [1] * 20
    secrets.SystemRandom().shuffle(fresh_labels)
    for i, expected in enumerate(fresh_labels):
        if expected == 0:
            data = rng.normal(0, 1.0, 10000).astype(np.float32)
        else:
            data = rng.laplace(0, 0.70710678, 10000).astype(np.float32)
        cases.append((data, expected, f"fresh_{i}"))

    secrets.SystemRandom().shuffle(cases)
    failures = {0: [], 1: []}

    # Every invocation receives an opaque randomized path in one common directory.
    with tempfile.TemporaryDirectory(prefix="detector_eval_") as staged_dir:
        staged = []
        for data, expected, source_name in cases:
            staged_path = os.path.join(staged_dir, secrets.token_hex(16) + ".h5")
            with h5py.File(staged_path, 'w') as f:
                f.create_dataset('/sensor_data', data=data)
            staged.append((staged_path, expected, source_name))

        secrets.SystemRandom().shuffle(staged)
        for staged_path, expected, source_name in staged:
            result = subprocess.run(
                ["python3", detector_path, staged_path],
                capture_output=True,
            )
            if result.returncode != expected:
                failures[expected].append(source_name)

    if failures[0]:
        pytest.fail(
            f"{len(failures[0])} clean samples modified: "
            + ", ".join(failures[0])
        )
    if failures[1]:
        pytest.fail(
            f"{len(failures[1])} evil samples bypassed: "
            + ", ".join(failures[1])
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
