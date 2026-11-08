#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile
import pytest


def load_original_measurements():
    """Read the original database through the deleted file descriptor still held by run_sensor.sh."""
    source_fd = None
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\x00', b' ')
            if b'/home/user/run_sensor.sh' not in cmdline:
                continue

            fd_dir = f'/proc/{pid}/fd'
            for fd in os.listdir(fd_dir):
                fd_path = os.path.join(fd_dir, fd)
                try:
                    target = os.readlink(fd_path)
                except OSError:
                    continue
                if 'sensor_data.db' in target and '(deleted)' in target:
                    source_fd = fd_path
                    break
            if source_fd:
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    assert source_fd is not None, "Could not locate the deleted sensor database file descriptor."

    temp = tempfile.NamedTemporaryFile(prefix='original_sensor_', suffix='.db', delete=False)
    temp_path = temp.name
    temp.close()
    try:
        with open(source_fd, 'rb') as src, open(temp_path, 'wb') as dst:
            shutil.copyfileobj(src, dst)

        conn = sqlite3.connect(temp_path)
        try:
            tables = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            ).fetchall()
            rows = conn.execute("SELECT * FROM measurements ORDER BY rowid").fetchall()
            total = conn.execute("SELECT SUM(value) FROM measurements").fetchone()[0]
        finally:
            conn.close()
        return tables, rows, total
    finally:
        os.unlink(temp_path)


def test_recovered_db_exists_and_valid():
    """Verify that recovered.db is valid and contains the original sensor data."""
    db_path = '/home/user/recovered.db'
    assert os.path.exists(db_path), f"File {db_path} does not exist."
    assert os.path.isfile(db_path), f"{db_path} is not a file."

    expected_tables, expected_rows, _ = load_original_measurements()

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT SUM(value) FROM measurements;")
        result = cursor.fetchone()[0]
        assert result is not None, "The measurements table is empty or missing."

        actual_tables = cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        actual_rows = cursor.execute("SELECT * FROM measurements ORDER BY rowid").fetchall()
        conn.close()

        assert actual_tables == expected_tables, "Recovered database does not contain the original table set."
        assert actual_rows == expected_rows, "Recovered measurements do not match the original sensor data."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to open or query {db_path} as a SQLite database: {e}")


def test_result_txt_content():
    """Verify that result.txt contains exactly the correctly rounded original sum."""
    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"File {result_path} does not exist."
    assert os.path.isfile(result_path), f"{result_path} is not a file."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    _, _, original_total = load_original_measurements()
    expected = f"{original_total:.2f}"
    assert content == expected, f"Expected result.txt to contain '{expected}', but found '{content}'"
    assert content == "60.60", f"Expected result.txt to contain '60.60', but found '{content}'"


def test_run_sensor_process_still_running():
    """Verify that run_sensor.sh is still running in the background (was not killed)."""
    try:
        output = subprocess.check_output(['pgrep', '-f', 'run_sensor.sh'], text=True)
        assert output.strip() != "", "run_sensor.sh process was killed, but the instructions said not to kill it."
    except subprocess.CalledProcessError:
        pytest.fail("run_sensor.sh process was killed, but the instructions said not to kill it.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
