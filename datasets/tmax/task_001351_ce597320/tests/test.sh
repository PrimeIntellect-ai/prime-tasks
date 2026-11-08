#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/sim_filter/target/release/sim_filter"
PROJECT_DIR = "/home/user/sim_filter"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
THRESHOLD = 4.25


def run_filter(path):
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10).returncode


def expected_status(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
    std_dev = math.sqrt(variance)
    if std_dev == 0.0:
        return 0
    return 1 if any(abs(value - mean) / std_dev > THRESHOLD for value in values) else 0


def max_z(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
    std_dev = math.sqrt(variance)
    return 0.0 if std_dev == 0.0 else max(abs(value - mean) / std_dev for value in values)


def values_with_target_z(rng, target, length=100):
    values = [rng.uniform(-2.0, 2.0) for _ in range(length)]
    index = rng.randrange(length)
    low = max(values)
    high = low + 1000.0
    for _ in range(100):
        middle = (low + high) / 2.0
        values[index] = middle
        if max_z(values) < target:
            low = middle
        else:
            high = middle
    values[index] = (low + high) / 2.0
    assert abs(max_z(values) - target) < 1e-7
    return values


def test_binary_exists():
    """Verify that the compiled Rust binary exists at the specified path."""
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Did you compile in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "The release artifact is not a compiled Linux binary."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing from the Rust project."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "src/main.rs is missing from the Rust project."


def test_clean_corpus_accepted():
    """Verify that the binary accepts all clean corpus files (exit code 0)."""
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}."
    failed_files = []
    for file_path in clean_files:
        if run_filter(file_path) != 0:
            failed_files.append(os.path.basename(file_path))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected incorrectly): {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    """Verify that the binary rejects all evil corpus files (exit code 1)."""
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}."
    failed_files = []
    for file_path in evil_files:
        if run_filter(file_path) != 1:
            failed_files.append(os.path.basename(file_path))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted incorrectly): {', '.join(failed_files)}")


def test_generated_trajectories_against_recomputed_oracle():
    rng = random.Random(secrets.randbits(128))
    cases = []

    # Threshold-focused cases on both sides of 4.25, including close margins.
    for target in (3.75, 4.10, 4.24, 4.26, 4.40, 5.25):
        cases.append(values_with_target_z(rng, target, rng.randint(80, 180)))

    # Additional fresh trajectories with varied lengths, locations, scales, and outliers.
    for _ in range(18):
        length = rng.randint(30, 240)
        location = rng.uniform(-100.0, 100.0)
        scale = 10 ** rng.uniform(-2.0, 2.0)
        values = [location + scale * rng.uniform(-2.0, 2.0) for _ in range(length)]
        if rng.random() < 0.55:
            values[rng.randrange(length)] += scale * rng.uniform(12.0, 40.0)
        cases.append(values)

    expected = [expected_status(values) for values in cases]
    assert 0 in expected and 1 in expected, "Generated suite must contain stable and unstable trajectories."

    with tempfile.TemporaryDirectory(prefix="trajectory_checks_") as directory:
        order = list(range(len(cases)))
        rng.shuffle(order)
        failures = []
        for case_number in order:
            path = os.path.join(directory, f"input_{secrets.token_hex(10)}.json")
            times = [rng.uniform(-500.0, 500.0) for _ in cases[case_number]]
            with open(path, "w", encoding="utf-8") as output:
                json.dump({"time": times, "values": cases[case_number]}, output)
            actual = run_filter(path)
            if actual != expected[case_number]:
                failures.append((case_number, expected[case_number], actual, max_z(cases[case_number])))
        assert not failures, f"Incorrect classifications on generated trajectories: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
