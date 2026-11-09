#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import sqlite3
import subprocess
import tempfile
import pytest

SCRIPT_PATH = '/home/user/compliance_filter.py'


def run_filter(db_path, tx_path):
    return subprocess.run(
        ['python3', SCRIPT_PATH, '--db', db_path, '--tx', tx_path],
        capture_output=True,
        timeout=8,
    ).returncode


def test_compliance_filter():
    db_path = '/app/data/corp.db'

    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Script is not a regular file: {SCRIPT_PATH}"

    evil_corpus_dir = '/app/corpus/evil/'
    clean_corpus_dir = '/app/corpus/clean/'

    evil_files = glob.glob(os.path.join(evil_corpus_dir, '*.json'))
    clean_files = glob.glob(os.path.join(clean_corpus_dir, '*.json'))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for fpath in evil_files:
        if run_filter(db_path, fpath) != 1:
            evil_bypassed.append(os.path.basename(fpath))

    clean_modified = []
    for fpath in clean_files:
        if run_filter(db_path, fpath) != 0:
            clean_modified.append(os.path.basename(fpath))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_graph_and_transactions():
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix='audit_' + secrets.token_hex(6) + '_') as td:
        db_path = os.path.join(td, secrets.token_hex(8) + '.sqlite')

        # Random, non-sequential IDs prevent solutions from inferring clusters from IDs.
        ids = rng.sample(range(10000, 999999), 440)
        sizes = [260, 90, 55, 20]
        components = []
        offset = 0
        for size in sizes:
            components.append(ids[offset:offset + size])
            offset += size
        isolates = ids[offset:]

        edges = []
        for comp in components:
            # A long chain exercises deep connectivity. Edge orientation is mixed.
            for a, b in zip(comp, comp[1:]):
                edges.append((a, b) if rng.randrange(2) else (b, a))
            # Add branches/cycles without changing components.
            for _ in range(max(4, len(comp) // 5)):
                a, b = rng.sample(comp, 2)
                edges.append((a, b) if rng.randrange(2) else (b, a))
        rng.shuffle(edges)

        conn = sqlite3.connect(db_path)
        conn.execute('CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE ownership (parent_id INTEGER, child_id INTEGER)')
        conn.executemany('INSERT INTO entities VALUES (?, ?)',
                         [(node, 'Entity_' + secrets.token_hex(4)) for node in ids])
        conn.executemany('INSERT INTO ownership VALUES (?, ?)', edges)
        conn.commit()
        conn.close()

        # Independently derive connected components from the generated edge list.
        parent = {node: node for node in ids}

        def find(node):
            while parent[node] != node:
                parent[node] = parent[parent[node]]
                node = parent[node]
            return node

        def union(a, b):
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[rb] = ra

        for a, b in edges:
            union(a, b)

        cases = []
        # Explicitly cover strict threshold behavior and both connectivity outcomes.
        stored_parent, stored_child = edges[0]
        cases.append((stored_child, stored_parent, 90000.0))  # reverse traversal required
        cases.append((components[0][0], components[0][-1], 50000.0))
        cases.append((components[0][0], components[0][-1], 49999.99))
        cases.append((components[0][0], components[1][0], 120000.0))
        cases.append((isolates[0], isolates[1], 70000.0))

        amounts = [0.0, 49999.0, 50000.0, 50000.01, 75000.0, 250000.0]
        for _ in range(24):
            sender, receiver = rng.sample(ids, 2)
            cases.append((sender, receiver, rng.choice(amounts)))
        rng.shuffle(cases)

        failures = []
        for index, (sender, receiver, amount) in enumerate(cases):
            tx_path = os.path.join(td, secrets.token_hex(12) + '.json')
            with open(tx_path, 'w', encoding='utf-8') as tx_file:
                json.dump({
                    'tx_id': secrets.token_hex(10),
                    'sender_id': sender,
                    'receiver_id': receiver,
                    'amount': amount,
                }, tx_file)

            expected = 1 if amount > 50000.0 and find(sender) == find(receiver) else 0
            actual = run_filter(db_path, tx_path)
            if actual != expected:
                failures.append(
                    f"case {index}: sender={sender}, receiver={receiver}, "
                    f"amount={amount}, expected={expected}, actual={actual}"
                )

        assert not failures, '\n'.join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
