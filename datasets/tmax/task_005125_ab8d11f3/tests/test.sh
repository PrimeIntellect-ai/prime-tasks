#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

SERVICE_DIR = '/home/user/metrics_service'
DB_PATH = os.path.join(SERVICE_DIR, 'data.db')
WAL_PATH = os.path.join(SERVICE_DIR, 'data.db-wal')
MEMORY_PATH = os.path.join(SERVICE_DIR, 'memory.dump')
SOLVE_PATH = os.path.join(SERVICE_DIR, 'solve.py')
FINAL_PATH = os.path.join(SERVICE_DIR, 'final_metric.txt')


def read_multiplier():
    with open(MEMORY_PATH, 'rb') as f:
        dump = f.read()
    matches = re.findall(rb'SECRET_MULTIPLIER=(-?\d+)', dump)
    assert matches, 'No SECRET_MULTIPLIER=<integer> value was found in memory.dump.'
    return int(matches[0])


def read_measurements(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return [row[0] for row in conn.execute(
            'SELECT value FROM measurements ORDER BY id'
        ).fetchall()]
    finally:
        conn.close()


def run_solver():
    if os.path.exists(FINAL_PATH):
        os.remove(FINAL_PATH)
    subprocess.run(
        ['python3', SOLVE_PATH],
        cwd=SERVICE_DIR,
        check=True,
        timeout=15,
    )
    assert os.path.isfile(FINAL_PATH), 'solve.py did not create final_metric.txt.'
    with open(FINAL_PATH, 'r') as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        pytest.fail(f"The content of {FINAL_PATH} is not a valid number: '{content}'")


def test_wal_file_integrated():
    # The WAL file should be integrated, meaning it's either removed or empty (0 bytes)
    if os.path.exists(WAL_PATH):
        assert os.path.getsize(WAL_PATH) == 0, "The WAL file data.db-wal still contains uncommitted records. It must be fully checkpointed/integrated."


def test_recovered_database_contains_all_measurements():
    assert os.path.isfile(DB_PATH), 'The recovered data.db does not exist.'
    values = read_measurements(DB_PATH)
    assert values == [15.5, 24.2, 10.3], (
        'data.db does not directly contain all recovered measurements.'
    )


def test_solve_script_exists_and_computes_from_database():
    assert os.path.isfile(SOLVE_PATH), f'The required solver {SOLVE_PATH} does not exist.'

    multiplier = read_multiplier()
    backup_dir = tempfile.mkdtemp(prefix='metrics-verifier-')
    backup_db = os.path.join(backup_dir, 'data.db')
    shutil.copy2(DB_PATH, backup_db)
    probe_value = None

    try:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)

        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute('CREATE TABLE measurements (id INTEGER PRIMARY KEY, value REAL)')
            conn.executemany(
                'INSERT INTO measurements (value) VALUES (?)',
                [(1.25,), (2.75,)],
            )
            conn.commit()
        finally:
            conn.close()

        probe_value = run_solver()
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup_db, DB_PATH)
        shutil.rmtree(backup_dir)
        # Re-run against the recovered database so the required final artifact and
        # filesystem state correspond to the actual task input.
        run_solver()

    expected_probe = (1.25 + 2.75) * multiplier
    assert probe_value == expected_probe, (
        f'solve.py returned {probe_value} for a database whose correct metric is '
        f'{expected_probe}; it must calculate from the measurements rather than '
        'write a precomputed answer.'
    )

    if os.path.exists(WAL_PATH):
        assert os.path.getsize(WAL_PATH) == 0, (
            'Running solve.py left data.db-wal nonempty after recovery.'
        )


def test_final_metric_file_exists():
    assert os.path.isfile(FINAL_PATH), f"The final metric file {FINAL_PATH} does not exist."


def test_final_metric_value():
    with open(FINAL_PATH, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"The content of {FINAL_PATH} is not a valid number: '{content}'")

    values = read_measurements(DB_PATH)
    multiplier = read_multiplier()
    derived_value = sum(values) * multiplier
    assert val == derived_value, (
        f'The calculated metric {val} does not match the recovered database and '
        f'memory multiplier; expected {derived_value}.'
    )

    # Preserve the original assertion for this task instance.
    expected_value = 22950.0
    assert val == expected_value, f"The calculated metric {val} is incorrect. Expected {expected_value}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
