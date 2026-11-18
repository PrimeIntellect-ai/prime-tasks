#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import subprocess
import time

APP_DIR = '/app/processor'
SUBMITTED = '/app/processor/processor'
REBUILT = '/tmp/verified-processor'
DB = '/app/telemetry.db'
RESULT = '/app/result.txt'


def run_processor(executable, wav):
    if os.path.exists(RESULT):
        os.remove(RESULT)
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            [executable, wav],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=5.0,
        )
    except subprocess.TimeoutExpired:
        assert False, 'Execution timed out after 5 seconds. The file reading loop is likely still too slow.'
    return proc, time.perf_counter() - start


def install_database(rows):
    for suffix in ('', '-wal', '-shm', '-journal'):
        path = DB + suffix
        if os.path.exists(path):
            os.remove(path)
    conn = sqlite3.connect(DB)
    try:
        conn.execute('CREATE TABLE events (id TEXT, peak_amplitude REAL)')
        conn.executemany('INSERT INTO events (id, peak_amplitude) VALUES (?, ?)', rows)
        conn.commit()
    finally:
        conn.close()


def assert_success(executable, wav, expected):
    proc, elapsed = run_processor(executable, wav)
    assert proc.returncode == 0, (
        f'Execution failed with return code {proc.returncode}.\n'
        f'Stdout: {proc.stdout}\nStderr: {proc.stderr}'
    )
    assert os.path.isfile(RESULT), 'The output file /app/result.txt was not created.'
    with open(RESULT, 'r') as f:
        output = f.read().strip()
    assert output == expected, f'Incorrect result: expected {expected!r}, got {output!r}'
    assert elapsed <= 0.5, (
        f'Execution took {elapsed:.3f} seconds, threshold is 0.5 seconds. '
        'Optimize the file reading mechanism.'
    )


def test_final_state_and_behavior():
    # Preserve the original verifier's executable and fixed-fixture assertions.
    assert os.path.isfile(SUBMITTED), (
        'The compiled executable /app/processor/processor is missing. Did you compile the application?'
    )
    assert os.access(SUBMITTED, os.X_OK), 'The file /app/processor/processor is not executable.'
    assert_success(SUBMITTED, '/app/telemetry.wav', 'EVT-9942')

    # Compile the submitted source so the checked executable must come from main.go.
    build = subprocess.run(
        ['go', 'build', '-o', REBUILT, '.'],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f'Go source does not compile.\nStdout: {build.stdout}\nStderr: {build.stderr}'
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)

    backup_db = '/tmp/original-telemetry.db'
    shutil.copy2(DB, backup_db)
    try:
        # A length that leaves a truncated final 10-byte record exercises the
        # required bounds handling. IDs are unpredictable until verification.
        truncated_wav = '/tmp/truncated-telemetry.wav'
        with open(truncated_wav, 'wb') as f:
            f.write(os.urandom(100003))

        expected1 = 'EVT-' + secrets.token_hex(8)
        decoy1 = 'EVT-' + secrets.token_hex(8)
        far1 = 'EVT-' + secrets.token_hex(8)
        install_database([
            (decoy1, 15042.49),
            (far1, 10000.0),
            (expected1, 15042.35),
        ])
        assert_success(REBUILT, truncated_wav, expected1)

        # Change both the database contents and expected ID, with a different
        # nearest in-tolerance amplitude, to reject fixed-output programs and
        # queries that merely return the first row in the tolerance window.
        expected2 = 'EVT-' + secrets.token_hex(8)
        decoy2 = 'EVT-' + secrets.token_hex(8)
        far2 = 'EVT-' + secrets.token_hex(8)
        install_database([
            (decoy2, 15042.55),
            (far2, 22000.0),
            (expected2, 15041.75),
        ])
        assert_success(REBUILT, truncated_wav, expected2)

        # The program must actually attempt to open its input rather than
        # producing a database-derived or constant answer without reading it.
        proc, _ = run_processor(REBUILT, '/tmp/definitely-missing-telemetry.wav')
        assert proc.returncode != 0, 'Processor succeeded even though its input WAV did not exist.'
        assert not os.path.exists(RESULT), 'Processor wrote a result without a readable input WAV.'
    finally:
        for suffix in ('', '-wal', '-shm', '-journal'):
            path = DB + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup_db, DB)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
