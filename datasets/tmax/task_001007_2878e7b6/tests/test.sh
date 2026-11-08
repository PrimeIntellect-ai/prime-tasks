#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import subprocess

import h5py
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
OUTPUT_PATH = "/home/user/stats_result.txt"
DATA_PATH = "/app/data/reads.h5"


def expected_stats(path):
    count = 0
    total = 0.0
    total_sq = 0.0

    with h5py.File(path, "r") as f:
        reads = f["reads"]
        for start in range(0, len(reads), 20000):
            values = np.asarray(reads[start:start + 20000])
            raw = values.view(np.uint8).reshape(len(values), values.dtype.itemsize)
            lengths = np.count_nonzero(raw, axis=1)
            gc_counts = np.count_nonzero((raw == ord("G")) | (raw == ord("C")), axis=1)
            fractions = gc_counts / lengths
            count += len(fractions)
            total += float(fractions.sum())
            total_sq += float(np.square(fractions).sum())

    mean = total / count
    variance = total_sq / count - mean * mean
    return mean, variance


def assert_output_matches(path):
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    match = re.fullmatch(r"Mean: (\d+\.\d{4}), Variance: (\d+\.\d{4})", content)
    assert match, f"Output file content '{content}' does not match the required format."

    mean, variance = expected_stats(path)
    expected = f"Mean: {mean:.4f}, Variance: {variance:.4f}"
    assert content == expected, f"Output file content '{content}' does not match independently calculated result '{expected}'."


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Pipeline script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Pipeline script {SCRIPT_PATH} is not executable."


def test_makefile_fixed():
    makefile_path = "/app/seqcalc-1.0/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-fopenmp" in content, "Makefile does not contain '-fopenmp'. The OpenMP flag was not added."


def test_pipeline_execution_time_and_output():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    start_time = time.time()
    try:
        subprocess.run([SCRIPT_PATH], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Pipeline script failed with error: {e.stderr.decode()}")
    execution_time = time.time() - start_time

    assert execution_time <= 4.0, f"Pipeline execution time was {execution_time:.2f}s, which is greater than the threshold of 4.0s. Did you recompile seqcalc with OpenMP?"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created by the pipeline."
    assert_output_matches(DATA_PATH)


def test_pipeline_on_unseen_data():
    backup_path = f"{DATA_PATH}.verifier-backup-{os.getpid()}"
    old_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            old_output = f.read()

    os.replace(DATA_PATH, backup_path)
    try:
        rng = np.random.default_rng()
        if int(rng.integers(0, 2)) == 0:
            gc_probability = float(rng.uniform(0.15, 0.35))
        else:
            gc_probability = float(rng.uniform(0.65, 0.85))

        bases = np.where(rng.random((8192, 150)) < gc_probability, ord("G"), ord("A")).astype(np.uint8)
        sequences = np.array([row.tobytes() for row in bases], dtype="S150")
        with h5py.File(DATA_PATH, "w") as f:
            f.create_dataset("reads", data=sequences)

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        try:
            subprocess.run([SCRIPT_PATH], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Pipeline script failed on unseen input with error: {e.stderr.decode()}")

        assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created on unseen input."
        assert_output_matches(DATA_PATH)
    finally:
        if os.path.exists(DATA_PATH):
            os.remove(DATA_PATH)
        os.replace(backup_path, DATA_PATH)
        if old_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
