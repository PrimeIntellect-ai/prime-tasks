#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import uuid
import pytest

CPP_PATH = "/home/user/calc_restore_size.cpp"
BINARY_PATH = "/tmp/calc_restore_size_verifier"
DB_PATH = "/home/user/backups.db"
TARGETS_PATH = "/home/user/targets.txt"
REPORT_PATH = "/home/user/restore_report.txt"


def test_cpp_source_exists():
    """Check if the C++ source file exists."""
    assert os.path.isfile(CPP_PATH), f"C++ source file missing at {CPP_PATH}"


def test_restore_report_exists():
    """Check if the restore report file exists."""
    assert os.path.isfile(REPORT_PATH), f"Restore report missing at {REPORT_PATH}"


def get_expected_sizes(db_path, targets):
    """Compute the expected total size for each target using a recursive query."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE ancestor_backups AS (
        SELECT id, name, size_mb
        FROM backups
        WHERE name = ?

        UNION ALL

        SELECT b.id, b.name, b.size_mb
        FROM backups b
        INNER JOIN dependencies d ON b.id = d.parent_id
        INNER JOIN ancestor_backups ab ON ab.id = d.id
    )
    SELECT SUM(size_mb) FROM ancestor_backups;
    """

    expected_results = []
    for target in targets:
        cursor.execute(query, (target,))
        result = cursor.fetchone()
        if result and result[0] is not None:
            expected_results.append(f"{target}: {result[0]} MB")
        else:
            expected_results.append(f"{target}: 0 MB")

    conn.close()
    return expected_results


def test_restore_report_contents():
    """Check if the restore report has the correct computed contents."""
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.isfile(TARGETS_PATH), f"Targets file missing at {TARGETS_PATH}"

    with open(TARGETS_PATH, "r") as f:
        targets = [line.strip() for line in f if line.strip()]

    expected_lines = get_expected_sizes(DB_PATH, targets)

    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report, found {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch on line {i + 1}: expected '{expected}', got '{actual}'"


@pytest.fixture(scope="session")
def compiled_program():
    result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-lsqlite3", "-o", BINARY_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source failed to compile:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)
    return BINARY_PATH


def run_program(binary, name):
    result = subprocess.run(
        [binary, name],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program failed for {name!r} with exit code {result.returncode}: {result.stderr}"
    )
    assert result.stderr == "", f"Program wrote unexpected stderr for {name!r}: {result.stderr!r}"
    lines = result.stdout.splitlines()
    assert len(lines) == 1, f"Expected exactly one output line for {name!r}, got {result.stdout!r}"
    assert re.fullmatch(r"-?\d+", lines[0]), f"Output is not exactly an integer: {result.stdout!r}"
    return int(lines[0])


def test_source_uses_sqlite_prepared_recursive_query():
    with open(CPP_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    # Remove comments so merely mentioning required APIs in comments is insufficient.
    source_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source_without_comments = re.sub(r"//[^\n]*", "", source_without_comments)

    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source_without_comments), "SQLite database API is not used"
    assert re.search(r"\bsqlite3_prepare_v[23]\s*\(", source_without_comments), "No SQLite prepared statement is created"
    assert re.search(r"\bsqlite3_bind_text(?:64)?\s*\(", source_without_comments), "Backup name is not bound as a parameter"
    assert re.search(r"\bsqlite3_step\s*\(", source_without_comments), "Prepared statement is not executed"
    assert re.search(r"WITH\s+RECURSIVE", source_without_comments, flags=re.I), "Query does not contain a recursive CTE"
    assert "?" in source_without_comments, "Query has no parameter placeholder"


def test_compiled_program_matches_report(compiled_program):
    with open(TARGETS_PATH, "r") as f:
        targets = [line.strip() for line in f if line.strip()]
    with open(REPORT_PATH, "r") as f:
        report_lines = [line.strip() for line in f if line.strip()]

    program_lines = [f"{target}: {run_program(compiled_program, target)} MB" for target in targets]
    assert program_lines == report_lines, "Report results do not match the compiled C++ program"


def test_compiled_program_on_generated_recursive_data(compiled_program):
    """Exercise recursion and parameter binding on data unavailable when the solution was written."""
    token = uuid.uuid4().hex
    root_name = f"Verifier_' OR 1=1 --_{token}"
    middle_name = f"Verifier_Middle_{token}"
    leaf_name = f"Verifier_Leaf_{token}"
    decoy_name = f"Verifier_Decoy_{token}"

    conn = sqlite3.connect(DB_PATH)
    ids = []
    try:
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM backups").fetchone()[0]
        ids = [next_id, next_id + 1, next_id + 2, next_id + 3]
        conn.executemany(
            "INSERT INTO backups(id, name, size_mb) VALUES (?, ?, ?)",
            [
                (ids[0], root_name, 317),
                (ids[1], middle_name, 29),
                (ids[2], leaf_name, 7),
                (ids[3], decoy_name, 99991),
            ],
        )
        conn.executemany(
            "INSERT INTO dependencies(id, parent_id) VALUES (?, ?)",
            [(ids[1], ids[0]), (ids[2], ids[1])],
        )
        conn.commit()

        assert run_program(compiled_program, leaf_name) == 353
        assert run_program(compiled_program, middle_name) == 346
        assert run_program(compiled_program, root_name) == 317
    finally:
        if ids:
            conn.executemany("DELETE FROM dependencies WHERE id = ? OR parent_id = ?", [(i, i) for i in ids])
            conn.executemany("DELETE FROM backups WHERE id = ?", [(i,) for i in ids])
            conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
