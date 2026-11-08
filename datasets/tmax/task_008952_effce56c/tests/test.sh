#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
from collections import Counter

DB_PATH = "/home/user/dataset.db"
RESULT_PATH = "/home/user/result.txt"
C_FILE_PATH = "/home/user/fix_and_analyze.c"
BINARY_PATH = "/tmp/verifier_fix_and_analyze"


def reset_database(rows):
    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE citations (source INTEGER, target INTEGER)")
    conn.executemany("INSERT INTO citations (source, target) VALUES (?, ?)", rows)
    conn.execute("CREATE INDEX idx_stale ON citations(target)")
    conn.commit()
    conn.close()


def expected_result(rows):
    counts = Counter(target for _, target in rows)
    degree = max(counts.values())
    node = min(node for node, count in counts.items() if count == degree)
    return f"Top Node: {node}, Degree: {degree}"


def run_and_check(rows):
    reset_database(rows)
    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass

    proc = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        env={**os.environ, "PATH": "/usr/bin:/bin"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f"Compiled C program exited with {proc.returncode}. "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert os.path.isfile(RESULT_PATH), "C program did not create result.txt"
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert content == expected_result(rows), (
        f"Expected dynamically derived result {expected_result(rows)!r}, got {content!r}"
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        stale = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale'"
        ).fetchone()
        fresh = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_fresh'"
        ).fetchone()
        columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_fresh')")]
        assert stale is None, "C program did not drop idx_stale"
        assert fresh is not None, "C program did not create idx_fresh"
        assert "target" in columns, "C program did not create idx_fresh on target"
    finally:
        conn.close()


def test_00_compile_and_execute_c_program_on_derived_inputs():
    assert os.path.isfile(C_FILE_PATH), f"C file missing at {C_FILE_PATH}"
    assert os.path.getsize(C_FILE_PATH) > 0, "C source file is empty"

    compile_proc = subprocess.run(
        ["/usr/bin/gcc", C_FILE_PATH, "-o", BINARY_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_proc.returncode == 0, (
        f"fix_and_analyze.c failed to compile: {compile_proc.stderr}"
    )

    nm_proc = subprocess.run(
        ["/usr/bin/nm", "-D", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert nm_proc.returncode == 0, f"Could not inspect compiled program: {nm_proc.stderr}"
    symbols = nm_proc.stdout
    assert re.search(r"\bsqlite3_(?:open|open_v2)(?:@|$)", symbols), (
        "Compiled program does not use the SQLite C API to open the database"
    )
    assert re.search(r"\bsqlite3_(?:exec|get_table|prepare|prepare_v2|prepare_v3)(?:@|$)", symbols), (
        "Compiled program does not use the SQLite C API to execute SQL"
    )
    forbidden = re.search(
        r"\b(?:system|popen|fork|vfork|execl|execle|execlp|execv|execve|execvp|posix_spawn|posix_spawnp)(?:@|$)",
        symbols,
    )
    assert forbidden is None, (
        f"Compiled program uses forbidden process-launch API {forbidden.group(0)!r}"
    )

    ids = sorted(secrets.SystemRandom().sample(range(1000, 1000000), 4))
    rows_one = []
    source = 1
    for target, count in ((ids[0], 7), (ids[1], 3), (ids[2], 7), (ids[3], 1)):
        for _ in range(count):
            rows_one.append((source, target))
            source += 1
    secrets.SystemRandom().shuffle(rows_one)
    run_and_check(rows_one)

    ids = secrets.SystemRandom().sample(range(1000001, 2000000), 3)
    rows_two = []
    source = 100
    for target, count in ((ids[0], 2), (ids[1], 6), (ids[2], 4)):
        for _ in range(count):
            rows_two.append((source, target))
            source += 1
    secrets.SystemRandom().shuffle(rows_two)
    run_and_check(rows_two)

    original_rows = [
        (1, 10), (2, 10), (3, 10),
        (4, 42), (5, 42), (6, 42), (7, 42), (8, 42),
        (9, 99), (10, 99),
    ]
    run_and_check(original_rows)


def test_c_file_exists():
    """Test that the C program file exists."""
    assert os.path.isfile(C_FILE_PATH), f"C file missing at {C_FILE_PATH}"


def test_result_file_content():
    """Test that the result file exists and contains the correct output."""
    assert os.path.isfile(RESULT_PATH), f"Result file missing at {RESULT_PATH}"

    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = "Top Node: 42, Degree: 5"
    assert content == expected_content, f"Expected result file content to be '{expected_content}', but got '{content}'"


def test_database_indexes():
    """Test that the stale index was dropped and the fresh index was created."""
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale';")
    stale_index = cursor.fetchone()
    assert stale_index is None, "Index 'idx_stale' was not dropped."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_fresh';")
    fresh_index = cursor.fetchone()
    assert fresh_index is not None, "Index 'idx_fresh' was not created."

    cursor.execute("PRAGMA index_info('idx_fresh');")
    columns = [row[2] for row in cursor.fetchall()]
    assert 'target' in columns, "Index 'idx_fresh' is not on the 'target' column."

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
