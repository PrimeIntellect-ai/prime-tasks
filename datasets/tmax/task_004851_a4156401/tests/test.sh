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

MAKE_DIR = "/app/sqlite-amalgamation"
MAKEFILE = os.path.join(MAKE_DIR, "Makefile")
SQLITE_OBJ = os.path.join(MAKE_DIR, "sqlite3.o")
SOURCE = "/home/user/backup_validator.c"
BINARY = "/home/user/backup_validator"


def run_validator(binary, args, timeout=5):
    return subprocess.run(
        [binary] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def create_database(path, rows):
    connection = sqlite3.connect(path)
    try:
        connection.execute(
            "CREATE TABLE incremental_backups(id INTEGER PRIMARY KEY, parent_id INTEGER)"
        )
        connection.executemany(
            "INSERT INTO incremental_backups(id, parent_id) VALUES (?, ?)", rows
        )
        connection.commit()
    finally:
        connection.close()


def assert_classification(binary, database, expected_output, expected_status):
    result = run_validator(binary, [database])
    assert result.returncode == expected_status, (
        f"{binary} returned {result.returncode} for {database}; "
        f"expected {expected_status}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout == expected_output + "\n", (
        f"{binary} produced unexpected stdout for {database}: {result.stdout!r}"
    )


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"Makefile is missing at {MAKEFILE}."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "sqlite2.c" not in content, "The typo 'sqlite2.c' is still present in the Makefile."
    assert "sqlite3.c" in content, "The Makefile does not reference 'sqlite3.c' for compilation."

    if os.path.exists(SQLITE_OBJ):
        os.remove(SQLITE_OBJ)
    result = subprocess.run(
        ["make"], cwd=MAKE_DIR, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"Running make failed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(SQLITE_OBJ), "make did not produce sqlite3.o."
    elf = subprocess.run(
        ["readelf", "-h", SQLITE_OBJ], capture_output=True, text=True, timeout=10
    )
    assert elf.returncode == 0 and "REL (Relocatable file)" in elf.stdout, (
        "sqlite3.o is not a valid relocatable object file."
    )


def test_backup_validator_binary_exists():
    assert os.path.isfile(BINARY), f"Binary {BINARY} is missing. Did you compile the C program?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."

    elf = subprocess.run(["readelf", "-h", BINARY], capture_output=True, text=True, timeout=10)
    assert elf.returncode == 0 and "ELF" in elf.stdout, f"{BINARY} is not an ELF binary."
    symbols = subprocess.run(["nm", "-g", BINARY], capture_output=True, text=True, timeout=10)
    assert symbols.returncode == 0, "Could not inspect validator symbols."
    assert any(
        " T sqlite3_open" in line or " T sqlite3_open_v2" in line
        for line in symbols.stdout.splitlines()
    ), "The validator does not contain the vendored SQLite implementation."


def test_corpora_classification():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Directory {evil_dir} is missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.db')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.db')]

    assert len(clean_files) > 0, "No clean databases found in the corpus."
    assert len(evil_files) > 0, "No evil databases found in the corpus."

    clean_failures = []
    for db in clean_files:
        result = run_validator(BINARY, [db])
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            clean_failures.append(os.path.basename(db))

    evil_failures = []
    for db in evil_files:
        result = run_validator(BINARY, [db])
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            evil_failures.append(os.path.basename(db))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/failed: " + ", ".join(clean_failures))
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/failed: " + ", ".join(evil_failures))
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_rebuild_source_and_unseen_databases():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."
    assert os.path.isfile(SQLITE_OBJ), "sqlite3.o is missing after make."

    with tempfile.TemporaryDirectory(prefix="validator_tests_") as directory:
        rebuilt = os.path.join(directory, "rebuilt_validator")
        compile_result = subprocess.run(
            [
                "gcc", SOURCE, SQLITE_OBJ,
                "-I", MAKE_DIR,
                "-o", rebuilt,
                "-ldl", "-lpthread",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert compile_result.returncode == 0, (
            "backup_validator.c could not be compiled and linked against sqlite3.o. "
            f"stdout={compile_result.stdout!r}, stderr={compile_result.stderr!r}"
        )

        cases = [
            ([(100, None)], "ACCEPT", 0),
            ([(7, None), (42, 7), (88, 42), (100, 88)], "ACCEPT", 0),
            ([(100, 100)], "REJECT", 1),
            ([(100, 37), (37, 100)], "REJECT", 1),
            ([(100, 91), (91, 73), (73, 22), (22, 91)], "REJECT", 1),
            ([(5, None), (20, 5), (100, 20), (301, 302), (302, 301)], "ACCEPT", 0),
        ]

        for index, (rows, output, status) in enumerate(cases):
            name = f"case_{uuid.uuid4().hex}_{index}.db"
            database = os.path.join(directory, name)
            create_database(database, rows)
            # Exercise both the submitted executable and a fresh build of its C source.
            assert_classification(BINARY, database, output, status)
            assert_classification(rebuilt, database, output, status)

        for executable in (BINARY, rebuilt):
            no_args = run_validator(executable, [])
            assert no_args.returncode != 0, f"{executable} accepted zero arguments."
            two_args = run_validator(executable, [database, database])
            assert two_args.returncode != 0, f"{executable} accepted two arguments."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
