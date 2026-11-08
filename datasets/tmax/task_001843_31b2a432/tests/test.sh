#!/bin/bash
mkdir -p /logs/verifier

DB=/home/user/db/locks.db
BACKUP=/tmp/locks.db.verifier-backup
cp "$DB" "$BACKUP" 2>/dev/null || true
trap 'if [ -f "$BACKUP" ]; then cp "$BACKUP" "$DB"; fi' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess

import pytest

SOURCE = "/home/user/workspace/detect_deadlock.c"
BINARY = "/home/user/workspace/detect_deadlock_verified"
REPORT = "/home/user/workspace/deadlock_report.json"
DATABASE = "/home/user/db/locks.db"
BACKUP = "/tmp/locks.db.verifier-backup"


def run_program():
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        [BINARY],
        cwd="/home/user/workspace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"JSON report is missing at {REPORT}"


def load_and_validate_report():
    try:
        with open(REPORT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT} does not contain valid JSON.")

    assert isinstance(data, dict), "The JSON report must be an object."
    assert set(data.keys()) == {"cycle"}, "The JSON object must contain only the 'cycle' key."
    assert isinstance(data["cycle"], list), "The 'cycle' value must be a list."
    assert all(type(tx_id) is int for tx_id in data["cycle"]), "All cycle entries must be integer tx_ids."
    return data


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SOURCE), f"C source file is missing at {SOURCE}"

    result = subprocess.run(
        ["gcc", "-std=c11", "-O0", "-Wall", "-Wextra", SOURCE, "-lsqlite3", "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C program failed to compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), "Compilation did not produce an executable."

    run_program()
    yield


def test_c_file_exists():
    """Test that the C source file was created."""
    assert os.path.isfile(SOURCE), f"C source file is missing at {SOURCE}"


def test_json_report_exists():
    """Test that the deadlock report JSON file was created."""
    assert os.path.isfile(REPORT), f"JSON report is missing at {REPORT}"


def test_json_report_content():
    """Test that the deadlock report contains the correct cycle."""
    data = load_and_validate_report()
    assert "cycle" in data, "JSON report is missing the 'cycle' key."
    cycle = data["cycle"]
    assert isinstance(cycle, list), "The 'cycle' value must be a list."
    expected_cycle = [101, 102, 103]
    assert cycle == expected_cycle, f"Expected cycle {expected_cycle}, but got {cycle}."


def test_uses_sqlite_c_api():
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "Source must include sqlite3.h."

    nm = subprocess.run(["nm", "-D", BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    symbols = nm.stdout
    assert re.search(r"\bsqlite3_open(?:_v2)?(?:@|\b)", symbols), "Executable does not call sqlite3_open/sqlite3_open_v2."
    assert any(name in symbols for name in ("sqlite3_prepare", "sqlite3_prepare_v2", "sqlite3_exec", "sqlite3_get_table")), \
        "Executable does not use a SQLite query API."
    assert "sqlite3_close" in symbols, "Executable does not call sqlite3_close."

    linked = subprocess.run(["ldd", BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert "libsqlite3" in linked.stdout, "Executable is not linked to libsqlite3."


def create_database(cycle_length):
    rng = random.SystemRandom()
    cycle_ids = rng.sample(range(1000, 900000), cycle_length)
    lowest = min(cycle_ids)
    remaining = [x for x in cycle_ids if x != lowest]
    rng.shuffle(remaining)
    expected = [lowest] + remaining

    extras = []
    while len(extras) < 2:
        value = secrets.randbelow(900000) + 1000
        if value not in expected and value not in extras:
            extras.append(value)
    tail_id, isolated_id = extras

    if os.path.exists(DATABASE):
        os.unlink(DATABASE)
    con = sqlite3.connect(DATABASE)
    try:
        con.execute("CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, query TEXT)")
        con.execute("CREATE TABLE locks (resource_id INTEGER, tx_id INTEGER, status TEXT)")
        tx_rows = [(tx, f"query for {tx}") for tx in expected + extras]
        rng.shuffle(tx_rows)
        con.executemany("INSERT INTO transactions (tx_id, query) VALUES (?, ?)", tx_rows)

        base_resource = secrets.randbelow(500000) + 10000
        lock_rows = []
        for i, waiter in enumerate(expected):
            holder = expected[(i + 1) % len(expected)]
            resource = base_resource + i
            lock_rows.append((resource, waiter, "WAITING"))
            lock_rows.append((resource, holder, "HELD"))

        # A non-cycle transaction waits into the cycle, and another transaction
        # holds an unrelated resource. These ensure all records cannot simply be
        # returned as the cycle.
        tail_resource = base_resource + cycle_length + 10
        lock_rows.extend([
            (tail_resource, expected[0], "HELD"),
            (tail_resource, tail_id, "WAITING"),
            (tail_resource + 1, isolated_id, "HELD"),
        ])
        rng.shuffle(lock_rows)
        con.executemany("INSERT INTO locks (resource_id, tx_id, status) VALUES (?, ?, ?)", lock_rows)
        con.commit()
    finally:
        con.close()
    return expected


def test_program_derives_cycles_from_database():
    try:
        for cycle_length in (2, 4, 5):
            expected = create_database(cycle_length)
            run_program()
            data = load_and_validate_report()
            assert data["cycle"] == expected, (
                f"For the generated database, expected directed cycle {expected}, "
                f"but got {data['cycle']}."
            )
    finally:
        if os.path.isfile(BACKUP):
            shutil.copy2(BACKUP, DATABASE)
            run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
