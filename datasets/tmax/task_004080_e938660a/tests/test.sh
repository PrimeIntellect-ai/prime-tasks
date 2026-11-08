#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import statistics
import subprocess
import tempfile

PIPELINE_DIR = '/home/user/pipeline'
DB_PATH = os.path.join(PIPELINE_DIR, 'sensor.db')
SQL_PATH = os.path.join(PIPELINE_DIR, 'recovery.sql')
EXEC_PATH = os.path.join(PIPELINE_DIR, 'variance')
RESULT_PATH = os.path.join(PIPELINE_DIR, 'final_result.txt')
EXPECTED_VALUES = [
    1000000.001,
    1000000.002,
    1000000.003,
    1000000.004,
    1000000.005,
    1000000.006,
]


def read_values(path):
    assert os.path.isfile(path), f'Database not found at {path}'
    try:
        with sqlite3.connect(path) as conn:
            rows = conn.execute('SELECT value FROM readings ORDER BY id').fetchall()
        return [row[0] for row in rows]
    except sqlite3.Error as exc:
        raise AssertionError(f'Failed to read SQLite database {path}: {exc}')


def run_variance(values):
    input_data = ''.join(f'{value}\n' for value in values)
    try:
        proc = subprocess.run(
            [EXEC_PATH], input=input_data, text=True, capture_output=True,
            timeout=2, check=False, cwd=PIPELINE_DIR
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f'Running {EXEC_PATH} timed out')
    assert proc.returncode == 0, f'{EXEC_PATH} exited with {proc.returncode}'
    return proc.stdout.strip()


def regression_scripts():
    paths = []
    for name in ('test_variance.sh', 'test_variance.py'):
        path = os.path.join(PIPELINE_DIR, name)
        if os.path.isfile(path):
            paths.append(path)
    return paths


def run_regression(path):
    try:
        return subprocess.run(
            [path], cwd=PIPELINE_DIR, capture_output=True, text=True,
            timeout=5, check=False
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f'Regression test {path} timed out')


def test_database_restored():
    vals = read_values(DB_PATH)
    assert len(vals) >= 5, f'Expected at least 5 readings, found {len(vals)}'
    assert vals == EXPECTED_VALUES, f'Recovered readings are incorrect: {vals!r}'


def test_recovery_sql_is_repaired_and_recreates_database():
    assert os.path.isfile(SQL_PATH), f'Recovery SQL not found at {SQL_PATH}'
    fd, temp_db = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    os.unlink(temp_db)
    try:
        with open(SQL_PATH, 'r') as handle:
            sql = handle.read()
        try:
            conn = sqlite3.connect(temp_db)
            conn.executescript(sql)
            conn.close()
        except sqlite3.Error as exc:
            raise AssertionError(f'recovery.sql is not valid executable SQL: {exc}')
        # Reopen so an unterminated transaction cannot appear successfully restored.
        assert read_values(temp_db) == EXPECTED_VALUES, 'recovery.sql does not recreate the expected readings'
    finally:
        if os.path.exists(temp_db):
            os.unlink(temp_db)


def test_makefile_and_source_build_executable():
    if os.path.lexists(EXEC_PATH):
        os.unlink(EXEC_PATH)
    proc = subprocess.run(
        ['make', '-B'], cwd=PIPELINE_DIR, capture_output=True, text=True,
        timeout=15, check=False
    )
    assert proc.returncode == 0, f'make failed:\n{proc.stdout}\n{proc.stderr}'
    assert os.path.isfile(EXEC_PATH), f'Executable not produced at {EXEC_PATH}'
    assert os.access(EXEC_PATH, os.X_OK), f'File at {EXEC_PATH} is not executable'


def test_variance_executable_exists():
    assert os.path.isfile(EXEC_PATH), f'Executable not found at {EXEC_PATH}'
    assert os.access(EXEC_PATH, os.X_OK), f'File at {EXEC_PATH} is not executable'


def test_variance_program_correctness_on_independent_inputs():
    cases = [
        [1.0, 2.0, 4.0, 8.0],
        [1000000.001, 1000000.002, 1000000.003, 1000000.004, 1000000.005],
        [999999999.75, 1000000000.0, 1000000000.25, 1000000000.5],
        [-3.5, 2.25, 9.0, 11.75, 20.5],
    ]
    for values in cases:
        expected = f'{statistics.variance(values):.6f}'
        actual = run_variance(values)
        assert actual == expected, f'For {values!r}, expected {expected!r}, got {actual!r}'


def test_regression_script_exists_and_runs():
    paths = regression_scripts()
    assert paths, 'Neither test_variance.sh nor test_variance.py was found'
    for path in paths:
        assert os.access(path, os.X_OK), f'{path} is not executable'
        proc = run_regression(path)
        assert proc.returncode == 0, f'{path} failed with exit code {proc.returncode}: {proc.stdout} {proc.stderr}'


def test_regression_script_detects_incorrect_program():
    paths = regression_scripts()
    assert paths, 'Neither test_variance.sh nor test_variance.py was found'
    backup = EXEC_PATH + '.verifier-backup'
    if os.path.lexists(backup):
        os.unlink(backup)
    os.rename(EXEC_PATH, backup)
    try:
        with open(EXEC_PATH, 'w') as handle:
            handle.write('#!/bin/sh\necho 999999.000000\n')
        os.chmod(EXEC_PATH, 0o755)
        for path in paths:
            proc = run_regression(path)
            assert proc.returncode != 0, f'{path} accepted an intentionally incorrect variance program'
    finally:
        if os.path.lexists(EXEC_PATH):
            os.unlink(EXEC_PATH)
        os.rename(backup, EXEC_PATH)


def test_final_result_correct():
    assert os.path.isfile(RESULT_PATH), f'Final result file not found at {RESULT_PATH}'
    vals = read_values(DB_PATH)
    expected = f'{statistics.variance(vals):.6f}'
    with open(RESULT_PATH, 'r') as handle:
        actual = handle.read().strip()
    assert actual == expected, f'Expected final_result.txt to contain {expected!r}, found {actual!r}'


def test_variance_program_correctness_on_recovered_database():
    vals = read_values(DB_PATH)
    expected = f'{statistics.variance(vals):.6f}'
    actual = run_variance(vals)
    assert actual == expected, f'Expected C program to output {expected!r}, got {actual!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
