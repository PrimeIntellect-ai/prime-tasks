#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import statistics
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/sanitizer.sh"


def run_sanitizer(filepath):
    return subprocess.run([SCRIPT_PATH, filepath], capture_output=True).returncode


def test_sanitizer_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_sanitizer_clean_corpus():
    clean_dir = "/app/corpus/clean"
    clean_files = [f for f in glob.glob(os.path.join(clean_dir, "*")) if os.path.isfile(f)]
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected incorrectly (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_sanitizer_evil_corpus():
    evil_dir = "/app/corpus/evil"
    evil_files = [f for f in glob.glob(os.path.join(evil_dir, "*")) if os.path.isfile(f)]
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1). Offending files: {', '.join(failed_files)}")


def test_sanitizer_randomized_hidden_cases():
    with open("/app/train_master_ids.txt", encoding="utf-8") as f:
        train_ids = [line.strip() for line in f if line.strip()]
    with open("/app/baseline_line_counts.txt", encoding="utf-8") as f:
        counts = [int(line.strip()) for line in f if line.strip()]

    assert train_ids, "Training master ID list is empty."
    assert len(counts) >= 2, "At least two baseline counts are required."

    mean = statistics.mean(counts)
    sample_sd = statistics.stdev(counts)
    lower = mean - 1.96 * sample_sd
    upper = mean + 1.96 * sample_sd

    valid_counts = list(range(max(2, math.ceil(lower)), math.floor(upper) + 1))
    assert valid_counts, "The calculated interval contains no usable integer line count."

    low_outlier = math.ceil(lower) - 1
    high_outlier = math.floor(upper) + 1
    assert low_outlier >= 2 and low_outlier < lower
    assert high_outlier > upper

    rng = random.SystemRandom()
    hidden_dir = tempfile.mkdtemp(prefix="evaluation_", dir="/var/tmp")
    cases = []

    def add_case(expected, line_count, doc_id, marker=None):
        filename = uuid.uuid4().hex + ".txt"
        path = os.path.join(hidden_dir, filename)
        lines = [f"DOC_ID: {doc_id}"]
        while len(lines) < line_count:
            lines.append(f"Record {uuid.uuid4().hex}")
        if marker is not None:
            lines[rng.randrange(1, line_count)] = marker
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        cases.append((path, expected))

    # Valid, previously unseen documents at independently chosen in-range lengths.
    for _ in range(4):
        add_case(0, rng.choice(valid_counts), "HID_" + secrets.token_hex(10))

    # Each contamination rule is exercised independently on randomized paths.
    for train_id in rng.sample(train_ids, min(4, len(train_ids))):
        add_case(1, rng.choice(valid_counts), train_id)

    for _ in range(3):
        add_case(
            1,
            rng.choice(valid_counts),
            "HID_" + secrets.token_hex(10),
            "Random payload containing OMEGA-77-ECHO within the record",
        )

    add_case(1, low_outlier, "HID_" + secrets.token_hex(10))
    add_case(1, high_outlier, "HID_" + secrets.token_hex(10))

    # Near-matches must not trigger the exact codename or exact-ID rules.
    add_case(0, rng.choice(valid_counts), train_ids[0] + "_NOT_THE_SAME")
    add_case(
        0,
        rng.choice(valid_counts),
        "HID_" + secrets.token_hex(10),
        "A harmless reference to OMEGA-77-FOXTROT",
    )

    rng.shuffle(cases)
    failures = []
    for path, expected in cases:
        actual = run_sanitizer(path)
        if actual != expected:
            failures.append((os.path.basename(path), expected, actual))

    if failures:
        details = ", ".join(
            f"{name}: expected {expected}, got {actual}"
            for name, expected, actual in failures
        )
        pytest.fail(f"Randomized hidden cases failed: {details}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
