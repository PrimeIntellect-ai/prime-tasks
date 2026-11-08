#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

SCRIPT_FILE = '/home/user/analyze_backups.py'
DB_FILE = '/home/user/backups.db'
OUTPUT_FILE = '/home/user/total_successful_backup_size.txt'
EXPECTED_SUM = 520


def _run_script(timeout=5):
    assert os.path.exists(SCRIPT_FILE), f"The required script '{SCRIPT_FILE}' does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_FILE).st_mode), f"The path '{SCRIPT_FILE}' is not a regular file."

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f"'{SCRIPT_FILE}' is not valid Python: {exc}")

    imports_sqlite3 = any(
        (isinstance(node, ast.Import) and any(alias.name == 'sqlite3' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'sqlite3')
        for node in ast.walk(tree)
    )
    assert imports_sqlite3, "The script must use Python's built-in sqlite3 module."

    if os.path.lexists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    try:
        result = subprocess.run(
            ['python3', SCRIPT_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('The analysis script did not terminate; cycle handling may be missing.')

    assert result.returncode == 0, (
        f"The analysis script exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def _read_output():
    assert os.path.exists(OUTPUT_FILE), f"The output file '{OUTPUT_FILE}' does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"The path '{OUTPUT_FILE}' is not a regular file."
    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()
    assert content, f"The file '{OUTPUT_FILE}' is empty."
    assert re.fullmatch(r'[+-]?\d+', content), (
        f"The output must contain only an integer. Found: '{content}'"
    )
    return int(content)


def _remove_db_files():
    for suffix in ('', '-wal', '-shm', '-journal'):
        path = DB_FILE + suffix
        if os.path.lexists(path):
            os.remove(path)


def _create_case(rng):
    reachable = rng.sample(range(10, 500), 6)
    unreachable = rng.sample(range(600, 900), 2)

    statuses = ['SUCCESS', 'FAILED', 'SUCCESS', 'SUCCESS', 'FAILED', 'SUCCESS']
    rng.shuffle(statuses)
    jobs = [(1, 'SUCCESS', rng.randint(11, 97))]
    jobs.extend((job_id, status, rng.randint(13, 149)) for job_id, status in zip(reachable, statuses))
    jobs.extend([
        (unreachable[0], 'SUCCESS', rng.randint(151, 249)),
        (unreachable[1], 'FAILED', rng.randint(251, 349)),
    ])

    edges = [(1, reachable[0])]
    edges.extend((reachable[i], reachable[i + 1]) for i in range(len(reachable) - 1))
    edges.extend([
        (1, reachable[2]),
        (reachable[5], reachable[1]),
        (reachable[3], reachable[0]),
        (unreachable[0], unreachable[1]),
        (unreachable[1], unreachable[0]),
    ])

    expected = sum(size for job_id, status, size in jobs if job_id == 1 or job_id in reachable if status == 'SUCCESS')
    return jobs, edges, expected


def _install_case(jobs, edges):
    _remove_db_files()
    conn = sqlite3.connect(DB_FILE)
    try:
        conn.execute('CREATE TABLE jobs (id INTEGER PRIMARY KEY, status TEXT, size_mb INTEGER)')
        conn.execute('CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER)')
        conn.executemany('INSERT INTO jobs VALUES (?, ?, ?)', jobs)
        conn.executemany('INSERT INTO dependencies VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


@pytest.fixture(scope='session', autouse=True)
def execute_submission_on_original_database():
    temp_dir = tempfile.mkdtemp(prefix='backup-verifier-')
    saved_db = os.path.join(temp_dir, 'backups.db')
    assert os.path.isfile(DB_FILE), f"The database '{DB_FILE}' is missing."
    shutil.copy2(DB_FILE, saved_db)
    _run_script()
    yield saved_db
    _remove_db_files()
    shutil.copy2(saved_db, DB_FILE)
    shutil.rmtree(temp_dir, ignore_errors=True)


def test_output_file_exists():
    """Verify that the output file has been created."""
    assert os.path.exists(OUTPUT_FILE), f"The output file '{OUTPUT_FILE}' does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"The path '{OUTPUT_FILE}' is not a regular file."


def test_output_file_content():
    """Verify that the output file contains the correct aggregated size."""
    assert os.path.exists(OUTPUT_FILE), f"The output file '{OUTPUT_FILE}' does not exist."

    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()

    assert content, f"The file '{OUTPUT_FILE}' is empty."

    try:
        calculated_sum = int(content)
    except ValueError:
        pytest.fail(f"The content of '{OUTPUT_FILE}' is not a valid integer. Found: '{content}'")

    assert calculated_sum == EXPECTED_SUM, (
        f"The calculated sum is incorrect. "
        f"Expected {EXPECTED_SUM}, but found {calculated_sum}."
    )


def test_script_traverses_randomized_cyclic_graphs(execute_submission_on_original_database):
    saved_db = execute_submission_on_original_database
    rng = random.Random(secrets.randbits(128))
    try:
        for _ in range(3):
            jobs, edges, expected = _create_case(rng)
            _install_case(jobs, edges)
            _run_script()
            actual = _read_output()
            assert actual == expected, (
                f"Incorrect total for a generated cyclic dependency graph: "
                f"expected {expected}, found {actual}."
            )
    finally:
        _remove_db_files()
        shutil.copy2(saved_db, DB_FILE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
