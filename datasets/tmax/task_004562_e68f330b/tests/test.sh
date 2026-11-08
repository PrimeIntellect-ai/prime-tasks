#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import subprocess
import tempfile

import pytest

CPP_PATH = "/home/user/detector.cpp"
BINARY_PATH = "/home/user/detector"
ORACLE_PATH = "/app/deadlock_detector"


def run_detector(path, csv_path):
    try:
        result = subprocess.run(
            [path, csv_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out on a valid CSV input")
    return result.returncode


def test_agent_binary_exists_and_executable():
    assert os.path.exists(CPP_PATH), f"The source code is missing at {CPP_PATH}"
    assert os.path.isfile(CPP_PATH), f"The source path {CPP_PATH} is not a file"
    assert os.path.getsize(CPP_PATH) > 0, f"The source code at {CPP_PATH} is empty"
    assert os.path.exists(BINARY_PATH), f"The compiled binary is missing at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"The path {BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"The binary at {BINARY_PATH} is not executable"
    assert os.path.isfile(ORACLE_PATH), f"The legacy detector is missing at {ORACLE_PATH}"
    assert not filecmp.cmp(BINARY_PATH, ORACLE_PATH, shallow=False), \
        "The submitted binary must not be a byte-identical copy of the legacy detector"


def test_evil_corpus_rejected():
    evil_corpus_path = "/app/corpus/evil/"
    evil_files = [f for f in os.listdir(evil_corpus_path) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No CSV files found in the evil corpus directory."

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_corpus_path, filename)
        if run_detector(BINARY_PATH, filepath) != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil bypassed "
            f"(expected exit code 1). Offending files: {', '.join(bypassed_files)}"
        )


def test_clean_corpus_accepted():
    clean_corpus_path = "/app/corpus/clean/"
    clean_files = [f for f in os.listdir(clean_corpus_path) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No CSV files found in the clean corpus directory."

    modified_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_corpus_path, filename)
        if run_detector(BINARY_PATH, filepath) != 0:
            modified_files.append(filename)

    if modified_files:
        pytest.fail(
            f"{len(modified_files)} of {len(clean_files)} clean modified "
            f"(expected exit code 0). Offending files: {', '.join(modified_files)}"
        )


def make_hidden_cases(rng):
    cases = []

    # Guaranteed acyclic chains with unrelated noise and shuffled records.
    for _ in range(30):
        length = rng.randint(1, 18)
        tids = rng.sample(range(10000, 900000000), length + 1)
        rids = rng.sample(range(10000, 900000000), length)
        rows = []
        for i in range(length):
            rows.append((tids[i], rids[i], "WAITING"))
            rows.append((tids[i + 1], rids[i], "HELD"))
        for _ in range(rng.randint(0, 10)):
            rows.append((rng.randrange(10000, 900000000), rng.randrange(10000, 900000000), "HELD"))
        rng.shuffle(rows)
        cases.append(rows)

    # Guaranteed cycles of varying lengths, with shuffled rows and noise.
    for _ in range(30):
        length = rng.randint(1, 16)
        tids = rng.sample(range(10000, 900000000), length)
        rids = rng.sample(range(10000, 900000000), length)
        rows = []
        for i in range(length):
            rows.append((tids[i], rids[i], "WAITING"))
            rows.append((tids[(i + 1) % length], rids[i], "HELD"))
        for _ in range(rng.randint(0, 10)):
            rows.append((rng.randrange(10000, 900000000), rng.randrange(10000, 900000000), rng.choice(("HELD", "WAITING"))))
        rng.shuffle(rows)
        cases.append(rows)

    # Arbitrary bipartite graphs, including duplicates and multiple holders/waiters.
    for _ in range(50):
        tids = rng.sample(range(10000, 900000000), rng.randint(2, 25))
        rids = rng.sample(range(10000, 900000000), rng.randint(2, 25))
        rows = [
            (rng.choice(tids), rng.choice(rids), rng.choice(("HELD", "WAITING")))
            for _ in range(rng.randint(1, 140))
        ]
        if rng.random() < 0.3:
            rows.extend(rng.choices(rows, k=rng.randint(1, min(8, len(rows)))))
        rng.shuffle(rows)
        cases.append(rows)

    # One larger graph exercises traversal without relying on a fixed corpus path.
    tids = rng.sample(range(1000000000, 1900000000), 1800)
    rids = rng.sample(range(2000000000, 2900000000), 1800)
    large = []
    for i in range(1799):
        large.append((tids[i], rids[i], "WAITING"))
        large.append((tids[i + 1], rids[i], "HELD"))
    rng.shuffle(large)
    cases.append(large)

    rng.shuffle(cases)
    return cases


def test_hidden_generated_inputs_match_legacy_detector():
    rng = random.SystemRandom()
    cases = make_hidden_cases(rng)

    with tempfile.TemporaryDirectory(prefix="graphcheck_") as directory:
        for index, rows in enumerate(cases):
            filename = f"input_{rng.getrandbits(96):024x}_{index}.csv"
            filepath = os.path.join(directory, filename)
            line_ending = "\r\n" if rng.random() < 0.35 else "\n"
            with open(filepath, "w", newline="") as csv_file:
                for transaction_id, resource_id, status in rows:
                    csv_file.write(f"{transaction_id},{resource_id},{status}{line_ending}")

            expected = run_detector(ORACLE_PATH, filepath)
            assert expected in (0, 1), \
                f"Legacy detector returned unexpected code {expected}"
            actual = run_detector(BINARY_PATH, filepath)
            assert actual == expected, \
                f"Detector disagreed with the legacy engine on generated case {index}: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
