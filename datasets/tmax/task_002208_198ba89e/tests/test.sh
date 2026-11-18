#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import secrets
import sqlite3
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/detector.sh"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"


def test_detector_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean directory {CLEAN_DIR} is missing."

    files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(files) > 0, "No clean databases found."

    failed_files = []
    for f in files:
        db_path = os.path.join(CLEAN_DIR, f)
        result = subprocess.run([SCRIPT_PATH, db_path], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            failed_files.append((f, result.returncode, output))

    if failed_files:
        msg = f"{len(failed_files)} of {len(files)} clean modified (rejected).\n"
        for f, rc, out in failed_files:
            msg += f"File: {f}, Exit code: {rc}, Output: '{out}'\n"
        pytest.fail(msg)


def test_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil directory {EVIL_DIR} is missing."

    files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(files) > 0, "No evil databases found."

    failed_files = []
    for f in files:
        db_path = os.path.join(EVIL_DIR, f)
        result = subprocess.run([SCRIPT_PATH, db_path], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "CORRUPTED":
            failed_files.append((f, result.returncode, output))

    if failed_files:
        msg = f"{len(failed_files)} of {len(files)} evil bypassed.\n"
        for f, rc, out in failed_files:
            msg += f"File: {f}, Exit code: {rc}, Output: '{out}'\n"
        pytest.fail(msg)


def derive_is_clean(db_path):
    conn = sqlite3.connect(db_path)
    try:
        nodes = [row[0] for row in conn.execute("SELECT id FROM nodes")]
        edges = list(conn.execute("SELECT src, dst FROM edges"))
        actual = collections.Counter(conn.execute("SELECT node_id, degree FROM index_stats"))
    finally:
        conn.close()

    expected = collections.Counter(
        (node_id, sum(1 for src, dst in edges if src == node_id or dst == node_id))
        for node_id in nodes
    )
    return actual == expected


def make_case(path, rng, corruption):
    conn = sqlite3.connect(path)
    try:
        conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY)")
        conn.execute("CREATE TABLE edges (src INTEGER, dst INTEGER)")
        conn.execute("CREATE TABLE index_stats (node_id INTEGER, degree INTEGER)")

        node_ids = sorted(rng.sample(range(10, 10000), rng.randint(6, 22)))
        conn.executemany("INSERT INTO nodes(id) VALUES (?)", [(n,) for n in node_ids])

        edges = []
        for _ in range(rng.randint(8, 45)):
            edges.append((rng.choice(node_ids), rng.choice(node_ids)))
        conn.executemany("INSERT INTO edges(src, dst) VALUES (?, ?)", edges)

        stats = [
            (node_id, sum(1 for src, dst in edges if src == node_id or dst == node_id))
            for node_id in node_ids
        ]
        rng.shuffle(stats)
        conn.executemany("INSERT INTO index_stats(node_id, degree) VALUES (?, ?)", stats)

        if corruption == "wrong":
            node_id, degree = rng.choice(stats)
            conn.execute(
                "UPDATE index_stats SET degree = ? WHERE node_id = ?",
                (degree + rng.randint(1, 20), node_id),
            )
        elif corruption == "missing":
            node_id, _ = rng.choice(stats)
            conn.execute("DELETE FROM index_stats WHERE node_id = ?", (node_id,))
        elif corruption == "stale":
            stale_id = max(node_ids) + rng.randint(1, 1000)
            conn.execute(
                "INSERT INTO index_stats(node_id, degree) VALUES (?, ?)",
                (stale_id, rng.randint(0, 20)),
            )
        elif corruption != "clean":
            raise AssertionError(f"Unknown case type: {corruption}")

        conn.commit()
    finally:
        conn.close()


def test_randomized_unlabelled_databases():
    rng = random.SystemRandom()
    root = tempfile.mkdtemp(prefix="graph-check-")
    cases = []
    kinds = ["clean", "wrong", "missing", "stale"] * 4
    rng.shuffle(kinds)

    for kind in kinds:
        path = os.path.join(root, secrets.token_hex(12) + ".sqlite")
        make_case(path, rng, kind)
        expected_clean = derive_is_clean(path)
        assert expected_clean == (kind == "clean")
        cases.append((path, expected_clean))

    rng.shuffle(cases)
    failures = []
    for path, expected_clean in cases:
        result = subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, text=True, timeout=20
        )
        expected_rc = 0 if expected_clean else 1
        expected_output = "CLEAN" if expected_clean else "CORRUPTED"
        if result.returncode != expected_rc or result.stdout.strip() != expected_output:
            failures.append(
                (os.path.basename(path), expected_rc, expected_output,
                 result.returncode, result.stdout.strip())
            )

    if failures:
        msg = "Detector failed dynamically generated, unlabelled databases.\n"
        for name, erc, eout, rc, out in failures:
            msg += (
                f"File: {name}, expected ({erc}, '{eout}'), "
                f"got ({rc}, '{out}')\n"
            )
        pytest.fail(msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
