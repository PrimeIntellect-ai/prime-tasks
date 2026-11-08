#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import subprocess
import tempfile
import uuid
from collections import defaultdict

import pytest

BINARY_PATH = "/home/user/sanitiser"
HEADER = ['id', 'src', 'dst', 'tx_endpoint', 'rx_endpoint', 'bytes', 'timestamp']


def run_sanitiser(csv_file):
    try:
        return subprocess.run(
            [BINARY_PATH, csv_file],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitiser timed out while processing {csv_file}")


def test_sanitiser_binary_exists():
    binary_path = "/home/user/sanitiser"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist. Did you compile your C++ code?"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_clean_corpus():
    binary_path = "/home/user/sanitiser"
    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert len(clean_files) > 0, f"No clean CSV files found in {clean_dir}."

    failed_files = []
    for csv_file in clean_files:
        result = subprocess.run([binary_path, csv_file], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))

    assert not failed_files, f"{len(failed_files)} out of {len(clean_files)} clean files were incorrectly rejected (expected exit code 0). Offending files: {failed_files[:5]}..."


def test_evil_corpus():
    binary_path = "/home/user/sanitiser"
    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(evil_files) > 0, f"No evil CSV files found in {evil_dir}."

    failed_files = []
    for csv_file in evil_files:
        result = subprocess.run([binary_path, csv_file], capture_output=True)
        if result.returncode != 1:
            failed_files.append((os.path.basename(csv_file), result.returncode))

    assert not failed_files, f"{len(failed_files)} out of {len(evil_files)} evil files bypassed the sanitiser (expected exit code 1). Offending files and exit codes: {failed_files[:5]}..."


def oracle_exit_code(rows):
    by_origin = defaultdict(list)
    graph = defaultdict(list)
    nodes = set()

    for row in rows:
        tx = row['tx_endpoint']
        rx = row['rx_endpoint']
        by_origin[tx].append((int(row['timestamp']), int(row['bytes'])))
        graph[tx].append(rx)
        nodes.add(tx)
        nodes.add(rx)

    for values in by_origin.values():
        values.sort(key=lambda value: value[0])
        amounts = [amount for _, amount in values]
        for i in range(len(amounts)):
            if sum(amounts[max(0, i - 2):i + 1]) > 15000:
                return 1

    state = {}

    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for neighbour in graph.get(node, []):
            if visit(neighbour):
                return True
        state[node] = 2
        return False

    if any(visit(node) for node in nodes if state.get(node, 0) == 0):
        return 1
    return 0


def make_row(index, src, dst, tx, rx, amount, timestamp):
    return {
        'id': str(index),
        'src': src,
        'dst': dst,
        'tx_endpoint': tx,
        'rx_endpoint': rx,
        'bytes': str(amount),
        'timestamp': str(timestamp),
    }


def generated_batch(rng, kind, token):
    rows = []

    if kind == 'clean_dag':
        nodes = [f"{token}_N{i}" for i in range(rng.randint(7, 13))]
        count = rng.randint(12, 24)
        for i in range(count):
            left = rng.randrange(0, len(nodes) - 1)
            right = rng.randrange(left + 1, len(nodes))
            # The decoy src/dst fields deliberately contain cycles.
            src = f"{token}_D{i % 3}"
            dst = f"{token}_D{(i + 1) % 3}"
            rows.append(make_row(i, src, dst, nodes[left], nodes[right],
                                 rng.randint(100, 4500), 100000 + i * 7))

    elif kind == 'cycle':
        size = rng.randint(2, 7)
        nodes = [f"{token}_C{i}" for i in range(size)]
        for i in range(size):
            # Decoy columns form an acyclic chain while true endpoints cycle.
            rows.append(make_row(i, f"{token}_S{i}", f"{token}_S{i + 1}",
                                 nodes[i], nodes[(i + 1) % size],
                                 rng.randint(100, 2500), 200000 + i * 11))

    elif kind == 'rolling':
        tx = f"{token}_HOT"
        amounts = [rng.randint(5200, 7200) for _ in range(3)]
        for i, amount in enumerate(amounts):
            rows.append(make_row(i, f"{token}_S{i}", f"{token}_S{i + 1}",
                                 tx, f"{token}_R{i}", amount,
                                 300000 + i * 13))
        # Add unrelated partitions so a solution must partition by tx_endpoint.
        for i in range(3, 8):
            rows.append(make_row(i, f"{token}_S{i}", f"{token}_S{i + 1}",
                                 f"{token}_P{i}", f"{token}_R{i}",
                                 rng.randint(200, 3500), 300000 + i * 13))

    elif kind == 'window_boundary':
        tx = f"{token}_WINDOW"
        # Total is over the limit, but every current-plus-previous-two window
        # is exactly 15000, which remains clean because the rule is strict >.
        timestamps = [400040, 400010, 400030, 400020]
        for i, timestamp in enumerate(timestamps):
            rows.append(make_row(i, f"{token}_D{i % 2}", f"{token}_D{(i + 1) % 2}",
                                 tx, f"{token}_R{i}", 5000, timestamp))

    elif kind == 'ordered_rolling':
        tx = f"{token}_ORDER"
        # File order is harmless for the first three records, but timestamp
        # order creates a 15001-byte three-row window.
        specs = [
            (5000, 500010),
            (1, 500040),
            (5000, 500020),
            (5001, 500030),
        ]
        for i, (amount, timestamp) in enumerate(specs):
            rows.append(make_row(i, f"{token}_S{i}", f"{token}_S{i + 1}",
                                 tx, f"{token}_R{i}", amount, timestamp))
    else:
        raise AssertionError(kind)

    rng.shuffle(rows)
    return rows


def test_generated_hidden_batches():
    rng = random.SystemRandom()
    kinds = (
        ['clean_dag'] * 16
        + ['cycle'] * 14
        + ['rolling'] * 14
        + ['window_boundary'] * 8
        + ['ordered_rolling'] * 8
    )
    rng.shuffle(kinds)

    failures = []
    observed = set()
    with tempfile.TemporaryDirectory(prefix='telemetry_') as directory:
        cases = []
        for kind in kinds:
            token = uuid.uuid4().hex
            rows = generated_batch(rng, kind, token)
            expected = oracle_exit_code(rows)
            observed.add(expected)
            path = os.path.join(directory, uuid.uuid4().hex + '.csv')
            with open(path, 'w', newline='') as handle:
                writer = csv.DictWriter(handle, fieldnames=HEADER)
                writer.writeheader()
                writer.writerows(rows)
            cases.append((path, expected))

        assert observed == {0, 1}, "Generated tests must include both outcomes"
        rng.shuffle(cases)
        for path, expected in cases:
            actual = run_sanitiser(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

    assert not failures, (
        f"{len(failures)} generated hidden batches produced incorrect exit codes. "
        f"Examples (file, expected, actual): {failures[:5]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
