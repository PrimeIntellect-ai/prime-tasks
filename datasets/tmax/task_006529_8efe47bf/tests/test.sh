#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import hashlib
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/build_dataset.sh"
RAW_FILE = "/home/user/data/raw_features.csv"
SCORED_FILE = "/home/user/data/scored_features.csv"
BOOTSTRAP_FILE = "/home/user/data/train_bootstrap.csv"


def build_truth(seed):
    scored = []
    with open(RAW_FILE, "r") as f:
        for line in f:
            uid, x1, x2, x3 = line.strip().split(",")
            x1, x2, x3 = float(x1), float(x2), float(x3)
            score = 0.5 * x1 - 1.2 * x2 + 0.8 * x3 + 0.1
            L = 1 if score > 0 else 0
            scored.append(f"{uid},{x1},{x2},{x3},{score:.4f},{L}\n")

    S = seed
    a = 1103515245
    c = 12345
    m = 2147483648

    bootstrap = []
    for _ in range(100):
        S = (a * S + c) % m
        idx = S % 1000
        bootstrap.append(scored[idx])

    md5 = hashlib.md5("".join(bootstrap).encode("utf-8")).hexdigest()
    return scored, bootstrap, md5


def assert_generated_files(expected_scored, expected_bootstrap):
    assert os.path.isfile(SCORED_FILE), f"Missing {SCORED_FILE}"
    with open(SCORED_FILE, "r") as f:
        agent_scored = f.readlines()
    assert agent_scored == expected_scored, f"Content of {SCORED_FILE} does not match expected output."

    assert os.path.isfile(BOOTSTRAP_FILE), f"Missing {BOOTSTRAP_FILE}"
    with open(BOOTSTRAP_FILE, "r") as f:
        agent_bootstrap = f.readlines()
    assert agent_bootstrap == expected_bootstrap, f"Content of {BOOTSTRAP_FILE} does not match expected output."


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable"


def test_pipeline_execution():
    assert os.path.isfile(RAW_FILE), f"Raw features file missing at {RAW_FILE}"

    seed = 42
    expected_scored, expected_bootstrap, expected_md5 = build_truth(seed)

    result = subprocess.run(
        [SCRIPT_PATH, str(seed), expected_md5],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip().split("\n")
    assert "REPRODUCIBLE" in output, f"Expected 'REPRODUCIBLE' in stdout, got: {result.stdout}"
    assert result.stdout.strip() == "REPRODUCIBLE", f"Stdout must contain strictly REPRODUCIBLE, got: {result.stdout!r}"

    assert_generated_files(expected_scored, expected_bootstrap)


def test_pipeline_divergent():
    seed = 99
    expected_scored, expected_bootstrap, expected_md5 = build_truth(seed)
    wrong_md5 = "0" * 32
    assert wrong_md5 != expected_md5

    result = subprocess.run(
        [SCRIPT_PATH, str(seed), wrong_md5],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    output = result.stdout.strip().split("\n")
    assert "DIVERGENT" in output, f"Expected 'DIVERGENT' in stdout for wrong MD5, got: {result.stdout}"
    assert result.stdout.strip() == "DIVERGENT", f"Stdout must contain strictly DIVERGENT, got: {result.stdout!r}"

    assert_generated_files(expected_scored, expected_bootstrap)


def test_bootstrap_for_unpredictable_seeds():
    seeds = set()
    while len(seeds) < 4:
        seed = secrets.randbelow(2147483648)
        if seed not in (42, 99):
            seeds.add(seed)

    for seed in seeds:
        expected_scored, expected_bootstrap, expected_md5 = build_truth(seed)
        result = subprocess.run(
            [SCRIPT_PATH, str(seed), expected_md5],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, (
            f"Script failed for seed {seed} with return code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
        assert result.stdout.strip() == "REPRODUCIBLE", (
            f"Expected strictly REPRODUCIBLE for seed {seed}, got: {result.stdout!r}"
        )
        assert_generated_files(expected_scored, expected_bootstrap)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
