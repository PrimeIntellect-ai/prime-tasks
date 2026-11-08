#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest
import glob
import random
import secrets
import tempfile

SCRIPT_PATH = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/home/user/data_hidden/clean"
EVIL_CORPUS_DIR = "/home/user/data_hidden/evil"
SIMULATOR_PATH = "/app/sim_generator"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Target script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Target script {SCRIPT_PATH} is not executable."

def test_filter_behavior():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(evil_file))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean files modified/rejected (expected exit 0). Offending files: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil files bypassed/accepted (expected exit 1). Offending files: {', '.join(evil_failures)}")

    if error_messages:
        pytest.fail("\n".join(error_messages))

def test_filter_on_fresh_unlabeled_paths():
    assert os.path.isfile(SIMULATOR_PATH), f"Simulator missing: {SIMULATOR_PATH}"
    assert os.access(SIMULATOR_PATH, os.X_OK), f"Simulator is not executable: {SIMULATOR_PATH}"

    rng = random.SystemRandom()
    even_seeds = rng.sample(range(1000, 2000000, 2), 10)
    odd_seeds = rng.sample(range(1001, 2000000, 2), 10)
    cases = [(seed, 0) for seed in even_seeds] + [(seed, 1) for seed in odd_seeds]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="trajectory_cases_") as case_dir:
        generated = []
        for seed, expected_status in cases:
            # Random neutral names and a common directory reveal no expected label.
            path = os.path.join(case_dir, f"sample_{secrets.token_hex(12)}.csv")
            with open(path, "wb") as output:
                produced = subprocess.run(
                    [SIMULATOR_PATH, str(seed)],
                    stdout=output,
                    stderr=subprocess.PIPE,
                    check=False,
                )
            assert produced.returncode == 0, f"Simulator failed for seed {seed}"
            generated.append((path, expected_status))

        rng.shuffle(generated)
        for path, expected_status in generated:
            result = subprocess.run([SCRIPT_PATH, path], capture_output=True)
            if result.returncode != expected_status:
                failures.append(
                    f"{os.path.basename(path)} returned {result.returncode}, expected {expected_status}"
                )

    if failures:
        pytest.fail("Fresh trajectory classification failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
