#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

OUTPUT_PATH = "/home/user/recovery_output.txt"
SCRIPT_PATH = "/home/user/scripts/extract_secrets.py"
CORRUPT_DB = "/home/user/data/prod.db"
EXPECTED_LINES = [
    "1:ALPHA-992",
    "2:BRAVO-713",
    "3:CHARLIE-404",
    "4:DELTA-505",
]
EXPECTED_ROWS = [
    (1, "ALPHA-992"),
    (2, "BRAVO-713"),
    (3, "CHARLIE-404"),
    (4, "DELTA-505"),
]


def read_output():
    assert os.path.isfile(OUTPUT_PATH), f"The file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f.read().strip().splitlines()]


def run_extractor(db_path):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH, db_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Extraction script failed for {db_path}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return read_output()


def find_recovered_database():
    candidates = []
    for root in ("/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, _, filenames in os.walk(root):
            for filename in filenames:
                path = os.path.join(directory, filename)
                try:
                    if os.path.realpath(path) == os.path.realpath(CORRUPT_DB):
                        continue
                    if not os.path.isfile(path):
                        continue
                    with open(path, "rb") as f:
                        if f.read(16) != b"SQLite format 3\x00":
                            continue
                    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
                    try:
                        integrity = conn.execute("PRAGMA integrity_check").fetchall()
                        rows = conn.execute(
                            "SELECT id, secret_code FROM secrets ORDER BY id"
                        ).fetchall()
                    finally:
                        conn.close()
                    if integrity == [("ok",)] and rows == EXPECTED_ROWS:
                        candidates.append(path)
                except (OSError, sqlite3.Error):
                    continue
    assert candidates, (
        "No separate, valid recovered SQLite database containing the recovered "
        "secrets was found under /home/user or /tmp."
    )
    return candidates[0]


def test_recovery_output_exists():
    assert os.path.isfile(OUTPUT_PATH), (
        f"The file {OUTPUT_PATH} does not exist. Did you run the extraction script?"
    )


def test_recovery_output_content():
    content = read_output()
    assert len(content) == len(EXPECTED_LINES), (
        f"Expected {len(EXPECTED_LINES)} lines in {OUTPUT_PATH}, but found {len(content)}."
    )
    for i, expected in enumerate(EXPECTED_LINES):
        assert content[i].strip() == expected, (
            f"Line {i+1} mismatch: expected '{expected}', got '{content[i].strip()}'."
        )


def test_script_bug_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "range(len(records) + 1)" not in content, (
        "The extraction script still contains the off-by-one bug "
        "`range(len(records) + 1)`."
    )


def test_recovered_database_and_extractor_behavior():
    recovered_db = find_recovered_database()

    # The submitted script must successfully process the recovered artifact.
    assert run_extractor(recovered_db) == EXPECTED_LINES

    # Exercise the script on verifier-generated records so hardcoded output cannot pass.
    token = uuid.uuid4().hex.upper()
    dynamic_rows = [
        (7, f"TEST-{token}-A"),
        (19, f"TEST-{token}-B"),
        (42, f"TEST-{token}-C"),
    ]
    fd, dynamic_db = tempfile.mkstemp(prefix="extractor-check-", suffix=".db")
    os.close(fd)
    os.remove(dynamic_db)
    try:
        conn = sqlite3.connect(dynamic_db)
        try:
            conn.execute("CREATE TABLE secrets (id INTEGER PRIMARY KEY, secret_code TEXT)")
            conn.executemany(
                "INSERT INTO secrets (id, secret_code) VALUES (?, ?)", dynamic_rows
            )
            conn.commit()
        finally:
            conn.close()

        expected_dynamic = [f"{row_id}:{code}" for row_id, code in dynamic_rows]
        assert run_extractor(dynamic_db) == expected_dynamic
    finally:
        if os.path.exists(dynamic_db):
            os.remove(dynamic_db)

    # Restore and re-check the required final output using the recovered database.
    assert run_extractor(recovered_db) == EXPECTED_LINES
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
