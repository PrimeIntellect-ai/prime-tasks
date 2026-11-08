#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import csv
import subprocess
import tempfile
import random
import secrets
import pytest


def test_db_index_dropped():
    db_path = "/app/data/network.db"
    assert os.path.exists(db_path), f"Database missing at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale_cache';")
    result = cursor.fetchall()
    conn.close()

    assert len(result) == 0, "Index 'idx_stale_cache' was not dropped from the database."


def test_cumulative_report():
    db_path = "/app/data/network.db"
    assert os.path.exists(db_path), f"Database missing at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT sender, timestamp, SUM(amount) OVER (PARTITION BY sender ORDER BY timestamp) as cumulative_amount
        FROM transactions
    """)
    expected_rows = cursor.fetchall()
    conn.close()

    expected_rows_sorted = sorted([(str(r[0]), str(r[1]), float(r[2])) for r in expected_rows])

    csv_path = "/home/user/cumulative_report.csv"
    assert os.path.exists(csv_path), f"Cumulative report missing at {csv_path}"

    actual_rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row:
                continue
            try:
                actual_rows.append((str(row[0]), str(row[1]), float(row[2])))
            except ValueError:
                pytest.fail(f"Could not parse row in CSV: {row}")

    actual_rows_sorted = sorted(actual_rows)

    assert len(actual_rows_sorted) == len(expected_rows_sorted), "Number of rows in cumulative report does not match expected."

    for actual, expected in zip(actual_rows_sorted, expected_rows_sorted):
        assert actual[0] == expected[0], f"Sender mismatch: {actual[0]} != {expected[0]}"
        assert actual[1] == expected[1], f"Timestamp mismatch: {actual[1]} != {expected[1]}"
        assert abs(actual[2] - expected[2]) < 1e-5, f"Cumulative amount mismatch for {actual[0]} at {actual[1]}: {actual[2]} != {expected[2]}"


def test_classifier_corpus():
    script_path = "/home/user/classifier.py"
    assert os.path.exists(script_path), f"Classifier script missing at {script_path}"
    assert os.path.isfile(script_path), f"Classifier is not a file: {script_path}"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_failures = []
    evil_failures = []

    clean_count = 0
    evil_count = 0

    if os.path.exists(clean_dir):
        for f in os.listdir(clean_dir):
            if not f.endswith(".csv"):
                continue
            clean_count += 1
            file_path = os.path.join(clean_dir, f)
            result = subprocess.run(["python3", script_path, file_path], capture_output=True, text=True)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_failures.append(f)

    if os.path.exists(evil_dir):
        for f in os.listdir(evil_dir):
            if not f.endswith(".csv"):
                continue
            evil_count += 1
            file_path = os.path.join(evil_dir, f)
            result = subprocess.run(["python3", script_path, file_path], capture_output=True, text=True)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_failures.append(f)

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {clean_count} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {evil_count} evil bypassed: {', '.join(evil_failures)}")

    assert not error_msg, " | ".join(error_msg)


def _node_name():
    return "n" + secrets.token_hex(8)


def _classification(edges):
    incoming = {}
    outgoing = {}
    for source, target in edges:
        outgoing.setdefault(source, set()).add(target)
        outgoing.setdefault(target, set())
        incoming.setdefault(target, set()).add(source)
        incoming.setdefault(source, set())
    return "EVIL" if any(len(outgoing[node]) >= 5 and len(incoming[node]) == 0 for node in outgoing) else "CLEAN"


def test_classifier_generated_hidden_suite():
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing or not a file at {script_path}"

    rng = random.SystemRandom()
    cases = []

    # Guaranteed adversarial graphs with randomized node identities and noise.
    for _ in range(8):
        nodes = [_node_name() for _ in range(rng.randint(7, 12))]
        hub = nodes[0]
        edge_set = {(hub, target) for target in nodes[1:rng.randint(6, len(nodes))]}
        for source in nodes[1:]:
            for target in nodes[1:]:
                if source != target and rng.random() < 0.15:
                    edge_set.add((source, target))
        edges = list(edge_set)
        assert _classification(edges) == "EVIL"
        cases.append(edges)

    # Guaranteed clean graphs where every node has at most four outgoing neighbors.
    for _ in range(8):
        nodes = [_node_name() for _ in range(rng.randint(6, 12))]
        edge_set = set()
        for source in nodes:
            targets = [node for node in nodes if node != source]
            rng.shuffle(targets)
            for target in targets[:rng.randint(0, min(4, len(targets)))]:
                edge_set.add((source, target))
        edges = list(edge_set)
        assert _classification(edges) == "CLEAN"
        cases.append(edges)

    # High out-degree is clean when that node has an incoming edge.
    for _ in range(5):
        nodes = [_node_name() for _ in range(8)]
        hub = nodes[0]
        edges = [(hub, target) for target in nodes[1:7]]
        edges.append((nodes[7], hub))
        assert _classification(edges) == "CLEAN"
        cases.append(edges)

    # Additional arbitrary graphs have answers derived from their actual edges.
    for _ in range(20):
        nodes = [_node_name() for _ in range(rng.randint(2, 12))]
        probability = rng.uniform(0.05, 0.45)
        edges = []
        for source in nodes:
            for target in nodes:
                if source != target and rng.random() < probability:
                    edges.append((source, target))
        cases.append(edges)

    cases.append([])
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="graph_checks_") as temp_dir:
        for edges in cases:
            expected = _classification(edges)
            rng.shuffle(edges)
            file_path = os.path.join(temp_dir, secrets.token_hex(12) + ".csv")
            with open(file_path, "w", encoding="utf-8", newline="") as handle:
                handle.write("source,target,amount\n")
                if rng.random() < 0.5:
                    handle.write("\n")
                for source, target in edges:
                    amount = rng.randint(1, 100000) / 100.0
                    handle.write(f"{source},{target},{amount:.2f}\n")
                    if rng.random() < 0.12:
                        handle.write("\n")

            try:
                result = subprocess.run(
                    ["python3", script_path, file_path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Classifier timed out on generated input {os.path.basename(file_path)}")

            assert result.returncode == 0, (
                f"Classifier exited with status {result.returncode} on generated input: {result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"Generated graph was classified as {result.stdout.strip()!r}; expected {expected}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
