#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

C_FILE_PATH = "/home/user/process_backup.c"
EXEC_FILE_PATH = "/home/user/process_backup"
JSON_FILE_PATH = "/home/user/region_salaries.json"
DB_FILE_PATH = "/home/user/backup.db"


def test_c_file_exists_and_content():
    assert os.path.isfile(C_FILE_PATH), f"C source file {C_FILE_PATH} does not exist."

    with open(C_FILE_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    assert re.search(r'NOT\s+INDEXED', content, re.IGNORECASE), \
        "The C program does not contain the 'NOT INDEXED' clause as required."

    assert re.search(r'sqlite3_bind', content, re.IGNORECASE), \
        "The C program does not appear to use 'sqlite3_bind' for parameterized queries."

    # Require these constructs outside C comments as well.
    uncommented = re.sub(r'/\*.*?\*/|//[^\r\n]*', '', content,
                         flags=re.DOTALL | re.MULTILINE)
    assert re.search(r'NOT\s+INDEXED', uncommented, re.IGNORECASE), \
        "The 'NOT INDEXED' clause appears only in a comment."
    assert re.search(r'\bsqlite3_bind\w*\s*\(', uncommented, re.IGNORECASE), \
        "The sqlite3 bind call appears only in a comment."


def test_executable_exists():
    assert os.path.isfile(EXEC_FILE_PATH), f"Executable {EXEC_FILE_PATH} does not exist."
    assert os.access(EXEC_FILE_PATH, os.X_OK), f"File {EXEC_FILE_PATH} is not executable."
    with open(EXEC_FILE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "process_backup must be a compiled executable."


def test_json_output_correctness():
    assert os.path.isfile(JSON_FILE_PATH), f"JSON output file {JSON_FILE_PATH} does not exist."

    with open(JSON_FILE_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON file {JSON_FILE_PATH}: {e}")

    expected_data = [
        {"region": "EU", "total_salary": 170000},
        {"region": "NA", "total_salary": 210000},
        {"region": "SA", "total_salary": 75000}
    ]

    assert isinstance(data, list), "JSON output must be a list of objects."
    assert data == expected_data, f"JSON data mismatch. Expected {expected_data}, but got {data}."


def test_program_executes_and_aggregates_current_database():
    token = secrets.token_hex(5).upper()
    regions = [f"AA{token}", f"MM{token}", f"ZZ{token}"]
    salaries = [
        secrets.randbelow(40000) + 10001,
        secrets.randbelow(40000) + 50001,
        secrets.randbelow(40000) + 90001,
        secrets.randbelow(40000) + 130001,
    ]

    tmpdir = tempfile.mkdtemp(prefix="process_backup_test_")
    original_db = os.path.join(tmpdir, "original.db")
    challenge_db = os.path.join(tmpdir, "challenge.db")
    rebuilt_exe = os.path.join(tmpdir, "process_backup_rebuilt")
    shutil.copy2(DB_FILE_PATH, original_db)

    old_json_exists = os.path.exists(JSON_FILE_PATH)
    old_json = None
    if old_json_exists:
        with open(JSON_FILE_PATH, 'rb') as f:
            old_json = f.read()

    try:
        conn = sqlite3.connect(DB_FILE_PATH)
        try:
            conn.execute("UPDATE employees SET status = 'INACTIVE'")
            conn.executemany(
                "INSERT INTO employees(name, region, salary, status) VALUES (?, ?, ?, ?)",
                [
                    ("Dynamic One", regions[1], salaries[0], "ACTIVE"),
                    ("Dynamic Two", regions[0], salaries[1], "ACTIVE"),
                    ("Dynamic Three", regions[1], salaries[2], "ACTIVE"),
                    ("Dynamic Four", regions[2], salaries[3], "ACTIVE"),
                    ("Inactive Distractor", regions[0], 987654321, "INACTIVE"),
                ],
            )
            conn.commit()
            rows = conn.execute(
                "SELECT region, SUM(salary) FROM employees NOT INDEXED "
                "WHERE status = ? GROUP BY region ORDER BY region",
                ("ACTIVE",),
            ).fetchall()
        finally:
            conn.close()

        expected = [
            {"region": region, "total_salary": total}
            for region, total in rows
        ]
        shutil.copy2(DB_FILE_PATH, challenge_db)
        challenge_hash = hashlib.sha256(open(challenge_db, 'rb').read()).hexdigest()

        compile_result = subprocess.run(
            ["gcc", C_FILE_PATH, "-o", rebuilt_exe, "-lsqlite3"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, \
            f"Submitted C source failed to compile: {compile_result.stderr}"

        for executable in (EXEC_FILE_PATH, rebuilt_exe):
            shutil.copy2(challenge_db, DB_FILE_PATH)
            for suffix in ("-wal", "-shm", "-journal"):
                try:
                    os.remove(DB_FILE_PATH + suffix)
                except FileNotFoundError:
                    pass
            try:
                os.remove(JSON_FILE_PATH)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, \
                f"{executable} exited with {result.returncode}: {result.stderr}"
            assert os.path.isfile(JSON_FILE_PATH), \
                f"{executable} did not create {JSON_FILE_PATH}."

            with open(JSON_FILE_PATH, 'r', encoding='utf-8') as f:
                try:
                    actual = json.load(f)
                except json.JSONDecodeError as e:
                    pytest.fail(f"{executable} produced invalid JSON: {e}")

            assert isinstance(actual, list), "JSON output must be a list of objects."
            assert actual == expected, \
                f"Program did not aggregate the current database correctly. Expected {expected}, got {actual}."
            current_hash = hashlib.sha256(open(DB_FILE_PATH, 'rb').read()).hexdigest()
            assert current_hash == challenge_hash, "The program must not modify the backup database."
    finally:
        shutil.copy2(original_db, DB_FILE_PATH)
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_FILE_PATH + suffix)
            except FileNotFoundError:
                pass
        if old_json_exists:
            with open(JSON_FILE_PATH, 'wb') as f:
                f.write(old_json)
        else:
            try:
                os.remove(JSON_FILE_PATH)
            except FileNotFoundError:
                pass
        shutil.rmtree(tmpdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
