#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess

SOURCE = "/home/user/analyzer.c"
EXECUTABLE = "/home/user/analyzer"
REBUILT = "/tmp/analyzer_rebuilt"
DB = "/home/user/backups.db"
LEAF_OUTPUT = "/home/user/leaf_chains.csv"
TOP_OUTPUT = "/home/user/top_ancestor.txt"

ORIGINAL_ROWS = [
    (1, None, 5000),
    (2, 1, 200),
    (3, 1, 150),
    (4, 2, 50),
    (5, 3, 75),
    (6, 4, 20),
    (7, 4, 30),
    (8, None, 2000),
    (9, 8, 100),
    (10, 9, 50),
]

DYNAMIC_CASES = [
    [
        (41, None, 13),
        (3, 41, 7),
        (88, 41, 2),
        (17, 3, 101),
        (25, 3, 11),
        (9, 88, 37),
        (60, 9, 5),
        (2, None, 1000),
        (77, 2, 4),
    ],
    [
        (20, None, 5),
        (4, 20, 6),
        (90, 4, 7),
        (3, None, 40),
        (70, 3, 2),
        (71, 70, 1),
        (1, None, 100),
    ],
]


def create_database(rows):
    if os.path.lexists(DB):
        assert os.path.isfile(DB), f"{DB} is not a regular file"
        os.unlink(DB)
    connection = sqlite3.connect(DB)
    try:
        connection.execute(
            "CREATE TABLE backups (id INTEGER PRIMARY KEY, parent_id INTEGER, size_mb INTEGER)"
        )
        connection.executemany("INSERT INTO backups VALUES (?, ?, ?)", rows)
        connection.commit()
    finally:
        connection.close()


def derive_expected(rows):
    records = {backup_id: (parent_id, size_mb) for backup_id, parent_id, size_mb in rows}
    parent_ids = {parent_id for _, parent_id, _ in rows if parent_id is not None}
    leaves = [backup_id for backup_id in records if backup_id not in parent_ids]

    leaf_results = []
    for leaf_id in leaves:
        total = 0
        current = leaf_id
        visited = set()
        while current is not None:
            assert current not in visited, "Test data unexpectedly contains a cycle"
            visited.add(current)
            parent_id, size_mb = records[current]
            total += size_mb
            current = parent_id
        leaf_results.append((leaf_id, total))
    leaf_results.sort(key=lambda item: item[1], reverse=True)

    descendant_counts = {backup_id: 0 for backup_id in records}
    for backup_id in records:
        current = records[backup_id][0]
        visited = set()
        while current is not None:
            assert current not in visited, "Test data unexpectedly contains a cycle"
            visited.add(current)
            descendant_counts[current] += 1
            current = records[current][0]

    top_id = min(descendant_counts, key=lambda backup_id: (-descendant_counts[backup_id], backup_id))
    leaf_text = "\n".join(f"{leaf_id},{total}" for leaf_id, total in leaf_results)
    return leaf_text, str(top_id)


def clear_outputs():
    for path in (LEAF_OUTPUT, TOP_OUTPUT):
        if os.path.lexists(path):
            assert os.path.isfile(path), f"{path} is not a regular file"
            os.unlink(path)


def run_and_check(binary, rows, explicit_original_check=False):
    create_database(rows)
    clear_outputs()
    completed = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{binary} exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.exists(LEAF_OUTPUT), f"Output file {LEAF_OUTPUT} does not exist."
    assert os.path.isfile(LEAF_OUTPUT), f"{LEAF_OUTPUT} is not a file."
    assert os.path.exists(TOP_OUTPUT), f"Output file {TOP_OUTPUT} does not exist."
    assert os.path.isfile(TOP_OUTPUT), f"{TOP_OUTPUT} is not a file."

    with open(LEAF_OUTPUT, "r") as handle:
        leaf_content = handle.read().strip().replace("\r", "")
    with open(TOP_OUTPUT, "r") as handle:
        top_content = handle.read().strip()

    expected_leaf, expected_top = derive_expected(rows)
    assert leaf_content == expected_leaf, (
        f"Content of {LEAF_OUTPUT} does not match expected output.\n"
        f"Expected:\n{expected_leaf}\nActual:\n{leaf_content}"
    )
    assert top_content == expected_top, (
        f"Content of {TOP_OUTPUT} does not match expected output.\n"
        f"Expected: '{expected_top}', Actual: '{top_content}'"
    )

    if explicit_original_check:
        original_leaf = "7,5280\n6,5270\n5,5225\n10,2150"
        assert leaf_content == original_leaf
        assert top_content == "1"


def assert_sqlite_linked(path):
    linked = subprocess.run(
        ["ldd", path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=10
    )
    assert linked.returncode == 0, f"Unable to inspect {path}:\n{linked.stdout}"
    assert "libsqlite3" in linked.stdout, f"{path} is not linked with libsqlite3"


def test_complete_analyzer():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    assert os.path.exists(EXECUTABLE), f"Executable file {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable"

    with open(SOURCE, "r", errors="replace") as handle:
        source_text = handle.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source_text), "Source does not include sqlite3.h"
    assert re.search(r"\bWITH\s+RECURSIVE\b", source_text, re.IGNORECASE), "Source does not use a recursive CTE"
    assert re.search(r"\bsqlite3_(?:open|open_v2)\s*\(", source_text), "Source does not open the database through the SQLite C API"
    assert re.search(r"\bsqlite3_(?:prepare(?:_v2|_v3)?|exec)\s*\(", source_text), "Source does not execute queries through the SQLite C API"

    assert_sqlite_linked(EXECUTABLE)

    build = subprocess.run(
        ["gcc", SOURCE, "-o", REBUILT, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"analyzer.c does not compile:\n{build.stdout}\n{build.stderr}"
    assert_sqlite_linked(REBUILT)

    run_and_check(EXECUTABLE, ORIGINAL_ROWS, explicit_original_check=True)
    for rows in DYNAMIC_CASES:
        run_and_check(EXECUTABLE, rows)

    run_and_check(REBUILT, ORIGINAL_ROWS)
    for rows in DYNAMIC_CASES:
        run_and_check(REBUILT, rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
