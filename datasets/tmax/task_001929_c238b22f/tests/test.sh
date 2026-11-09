#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/analyze_graph.sh"
CLEAN_CORPUS_DIR = "/app/tests/corpus/clean"
EVIL_CORPUS_DIR = "/app/tests/corpus/evil"
RNG = secrets.SystemRandom()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Expected a file at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert clean_files, f"No clean CSV files found in {CLEAN_CORPUS_DIR}"
    assert evil_files, f"No evil CSV files found in {EVIL_CORPUS_DIR}"

    clean_failures = []
    for f in clean_files:
        result = subprocess.run(["bash", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run(["bash", SCRIPT_PATH, f], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def has_directed_three_cycle(path):
    edges = set()
    vertices = set()
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source_account", "target_account", "amount", "timestamp"]
        for row in reader:
            source = row["source_account"]
            target = row["target_account"]
            vertices.add(source)
            vertices.add(target)
            edges.add((source, target))

    outgoing = {v: set() for v in vertices}
    for source, target in edges:
        outgoing[source].add(target)

    for a in vertices:
        for b in outgoing[a]:
            if b == a:
                continue
            for c in outgoing.get(b, ()):
                if c != a and c != b and a in outgoing.get(c, ()):
                    return True
    return False


def random_accounts(count):
    return ["acct_" + secrets.token_hex(8) for _ in range(count)]


def write_graph(directory, nodes, edges):
    path = os.path.join(directory, secrets.token_hex(12) + ".csv")
    rows = list(edges)
    RNG.shuffle(rows)
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source_account", "target_account", "amount", "timestamp"])
        for index, (source, target) in enumerate(rows):
            amount = f"{RNG.randrange(1, 100000)}.{RNG.randrange(100):02d}"
            timestamp = str(RNG.randrange(1_600_000_000, 2_000_000_000) + index)
            writer.writerow([source, target, amount, timestamp])
    return path


def isolated_cycle_graph(cycle_length):
    count = RNG.randrange(max(6, cycle_length + 1), 21)
    nodes = random_accounts(count)
    cycle_nodes = nodes[:cycle_length]
    edges = {
        (cycle_nodes[i], cycle_nodes[(i + 1) % cycle_length])
        for i in range(cycle_length)
    }

    # Add an independently ordered DAG on the remaining vertices. This varies
    # graph size and density without creating accidental cycles through the
    # deliberately isolated cycle component.
    remainder = nodes[cycle_length:]
    RNG.shuffle(remainder)
    probability = RNG.uniform(0.05, 0.55)
    for i in range(len(remainder)):
        for j in range(i + 1, len(remainder)):
            if RNG.random() < probability:
                edges.add((remainder[i], remainder[j]))
    return nodes, edges


def arbitrary_random_graph():
    count = RNG.randrange(4, 13)
    nodes = random_accounts(count)
    probability = RNG.uniform(0.03, 0.38)
    edges = set()
    for source in nodes:
        for target in nodes:
            if source != target and RNG.random() < probability:
                edges.add((source, target))
    return nodes, edges


def test_fresh_random_graphs():
    cases = []
    with tempfile.TemporaryDirectory(prefix="graph-validation-") as directory:
        # Include clean graphs with directed cycles of lengths other than three,
        # as well as malicious graphs with a directed triangular cycle.
        for i in range(24):
            cycle_length = 3 if i % 2 else RNG.choice([2, 4, 5])
            nodes, edges = isolated_cycle_graph(cycle_length)
            path = write_graph(directory, nodes, edges)
            expected = has_directed_three_cycle(path)
            assert expected == (cycle_length == 3)
            cases.append((path, expected))

        # Rejection-sample fully arbitrary directed graphs and independently
        # derive their answers from the CSV contents, obtaining both classes.
        wanted = {False: 10, True: 10}
        attempts = 0
        while wanted[False] or wanted[True]:
            attempts += 1
            assert attempts < 5000, "Unable to generate balanced random graph cases"
            nodes, edges = arbitrary_random_graph()
            path = write_graph(directory, nodes, edges)
            expected = has_directed_three_cycle(path)
            if wanted[expected] == 0:
                os.unlink(path)
                continue
            wanted[expected] -= 1
            cases.append((path, expected))

        RNG.shuffle(cases)
        failures = []
        for path, contains_triangle in cases:
            result = subprocess.run(["bash", SCRIPT_PATH, path], capture_output=True)
            expected_code = 1 if contains_triangle else 0
            if result.returncode != expected_code:
                failures.append(
                    f"{os.path.basename(path)} expected exit {expected_code}, got {result.returncode}"
                )

        if failures:
            pytest.fail("Random graph failures: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
