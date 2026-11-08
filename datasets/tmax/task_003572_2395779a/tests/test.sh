#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import sqlite3
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

DETECTOR = "/home/user/detector.py"
NX_SOURCE = "/app/networkx-source"
UNWEIGHTED = "/app/networkx-source/networkx/algorithms/shortest_paths/unweighted.py"


def detector_env():
    env = os.environ.copy()
    env["PYTHONPATH"] = NX_SOURCE + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    return env


def run_detector(db):
    result = subprocess.run(
        ["python3", DETECTOR, db],
        capture_output=True,
        text=True,
        env=detector_env(),
        timeout=15,
    )
    return result.stdout.strip()


def test_networkx_perturbation_fixed():
    assert os.path.isfile(UNWEIGHTED), f"File {UNWEIGHTED} is missing."
    with open(UNWEIGHTED, "r") as f:
        content = f.read()
    assert "cutoff -= 1" not in content, (
        f"The deliberate perturbation 'cutoff -= 1' is still present in {UNWEIGHTED}."
    )


def test_networkx_cutoff_behavior():
    probe = r'''
import os
import secrets
import networkx as nx

expected_root = os.path.realpath("/app/networkx-source") + os.sep
assert os.path.realpath(nx.__file__).startswith(expected_root), nx.__file__

nodes = [secrets.token_hex(8) for _ in range(6)]
g = nx.DiGraph()
for left, right in zip(nodes, nodes[1:]):
    g.add_edge(left, right)

for cutoff in range(5):
    forward = nx.single_source_shortest_path_length(g, nodes[0], cutoff=cutoff)
    assert forward[nodes[cutoff]] == cutoff
    if cutoff + 1 < len(nodes):
        assert nodes[cutoff + 1] not in forward

    target_index = len(nodes) - 1
    backward = nx.single_target_shortest_path_length(g, nodes[target_index], cutoff=cutoff)
    boundary = nodes[target_index - cutoff]
    assert backward[boundary] == cutoff
    if target_index - cutoff - 1 >= 0:
        assert nodes[target_index - cutoff - 1] not in backward
'''
    result = subprocess.run(
        ["python3", "-c", probe],
        capture_output=True,
        text=True,
        env=detector_env(),
        timeout=15,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR), f"Detector script {DETECTOR} does not exist."


def test_detector_evil_corpus():
    evil_path = "/home/user/corpora/evil/"
    evil_dbs = glob.glob(os.path.join(evil_path, "*.db")) + glob.glob(os.path.join(evil_path, "*.sqlite"))
    assert len(evil_dbs) > 0, f"No databases found in {evil_path}."

    failed_dbs = []
    for db in evil_dbs:
        output = run_detector(db)
        if output != "EVIL":
            failed_dbs.append((os.path.basename(db), output))

    if failed_dbs:
        pytest.fail(
            f"{len(failed_dbs)} of {len(evil_dbs)} evil bypassed. Offending files: "
            + ", ".join(f"{name} (output: {out})" for name, out in failed_dbs)
        )


def test_detector_clean_corpus():
    clean_path = "/home/user/corpora/clean/"
    clean_dbs = glob.glob(os.path.join(clean_path, "*.db")) + glob.glob(os.path.join(clean_path, "*.sqlite"))
    assert len(clean_dbs) > 0, f"No databases found in {clean_path}."

    failed_dbs = []
    for db in clean_dbs:
        output = run_detector(db)
        if output != "CLEAN":
            failed_dbs.append((os.path.basename(db), output))

    if failed_dbs:
        pytest.fail(
            f"{len(failed_dbs)} of {len(clean_dbs)} clean modified/flagged. Offending files: "
            + ", ".join(f"{name} (output: {out})" for name, out in failed_dbs)
        )


def create_db(path, transactions):
    conn = sqlite3.connect(path)
    try:
        conn.execute(
            "CREATE TABLE transactions "
            "(id INTEGER PRIMARY KEY, source_account TEXT, target_account TEXT, "
            "amount REAL, timestamp TEXT)"
        )
        conn.executemany(
            "INSERT INTO transactions "
            "(id, source_account, target_account, amount, timestamp) "
            "VALUES (?, ?, ?, ?, ?)",
            transactions,
        )
        conn.commit()
    finally:
        conn.close()


def make_transactions(a_kind, path_length):
    token = secrets.token_hex(6)
    source = "ACCOUNT_" + token
    base = datetime(2031, 7, 14, 22, 30)
    rows = []

    if a_kind == "true":
        # Four transactions straddling midnight, all in a rolling 24-hour window.
        specs = [(0, 12001.0), (2, 13002.0), (5, 14003.0), (9, 15004.0)]
    elif a_kind == "low_sum":
        specs = [(0, 12500.0), (2, 12500.0), (5, 12500.0), (9, 12500.0)]
    elif a_kind == "three_only":
        specs = [(0, 30000.0), (2, 30000.0), (5, 30000.0)]
    elif a_kind == "spread":
        specs = [(0, 20000.0), (30, 20000.0), (60, 20000.0), (90, 20000.0)]
    else:
        specs = []

    next_id = 1
    for hours, amount in specs:
        rows.append((
            next_id,
            source,
            "DEST_" + secrets.token_hex(5),
            amount,
            (base + timedelta(hours=hours)).isoformat(),
        ))
        next_id += 1

    if path_length is not None:
        start = "SANCTIONED_" + secrets.token_hex(5)
        end = "CLEARED_" + secrets.token_hex(5)
        intermediates = ["NODE_" + secrets.token_hex(5) for _ in range(max(0, path_length - 1))]
        path = [start] + intermediates + [end]
        for left, right in zip(path, path[1:]):
            rows.append((next_id, left, right, 17.0, base.isoformat()))
            next_id += 1

    return rows


def test_detector_on_unlabeled_generated_databases():
    # These databases live outside the visibly labeled corpora and are shuffled,
    # so their paths and invocation order do not reveal the expected answer.
    cases = [
        ("true", 1),
        ("true", 2),
        ("true", 3),
        ("true", 4),
        ("true", None),
        ("low_sum", 1),
        ("low_sum", 3),
        ("three_only", 2),
        ("three_only", 4),
        ("spread", 3),
        ("spread", None),
        ("none", 3),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="audit-inputs-") as directory:
        generated = []
        for a_kind, path_length in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".sqlite")
            create_db(path, make_transactions(a_kind, path_length))
            expected = "EVIL" if a_kind == "true" and path_length is not None and path_length <= 3 else "CLEAN"
            generated.append((path, expected))

        random.SystemRandom().shuffle(generated)
        for path, expected in generated:
            actual = run_detector(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

    assert not failures, "Generated database failures: " + ", ".join(
        f"{name}: expected {expected}, got {actual!r}"
        for name, expected, actual in failures
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
