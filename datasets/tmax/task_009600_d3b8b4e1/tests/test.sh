#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import sqlite3
import secrets
import shutil
import tempfile

SCRIPT_PATH = '/home/user/generate_audit_report.sh'
DB_PATH = '/home/user/audit.db'
CSV_PATH = '/home/user/violations.csv'

QUERY = """
    SELECT e.name, d.name, a.system_name, a.access_time
    FROM access_logs a
    JOIN employees e ON a.employee_id = e.id
    JOIN departments d ON e.department_id = d.id
    JOIN system_clearances s ON a.system_name = s.system_name
    WHERE e.clearance_level < s.required_clearance
    ORDER BY a.access_time ASC
"""

def expected_lines():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(QUERY).fetchall()
    finally:
        conn.close()
    return [','.join(map(str, row)) for row in rows]

def run_and_read_output():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed to execute with return code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), (
        f"Output file not found at {CSV_PATH} after running the script."
    )

    with open(CSV_PATH, 'r') as f:
        actual_content = f.read().strip()
    return [line.strip() for line in actual_content.split('\n') if line.strip()]

def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), (
        f"Script at {SCRIPT_PATH} is not executable by the owner."
    )

def test_script_execution_and_output():
    """Retain the original exact comparison against the provided database."""
    actual_csv_lines = run_and_read_output()
    expected_csv_lines = expected_lines()
    assert actual_csv_lines == expected_csv_lines, (
        f"CSV content mismatch.\n"
        f"Expected:\n{chr(10).join(expected_csv_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_csv_lines)}"
    )

def test_script_queries_changed_database():
    """Require the script to derive its report from database contents."""
    fd, backup_path = tempfile.mkstemp(prefix='audit-db-backup-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    try:
        token = secrets.token_hex(12)
        conn = sqlite3.connect(DB_PATH)
        try:
            department_id = conn.execute(
                'SELECT COALESCE(MAX(id), 0) + 100 FROM departments'
            ).fetchone()[0]
            employee_id = conn.execute(
                'SELECT COALESCE(MAX(id), 0) + 100 FROM employees'
            ).fetchone()[0]
            log_id = conn.execute(
                'SELECT COALESCE(MAX(log_id), 0) + 100 FROM access_logs'
            ).fetchone()[0]

            department_name = f'Compliance_{token}'
            employee_name = f'VerifierEmployee_{token}'
            system_name = f'VerifierSystem_{token}'
            access_time = f'2023-09-30 07:{secrets.randbelow(60):02d}:{secrets.randbelow(60):02d}'

            conn.execute(
                'INSERT INTO departments (id, name) VALUES (?, ?)',
                (department_id, department_name),
            )
            conn.execute(
                'INSERT INTO employees '
                '(id, name, department_id, clearance_level) VALUES (?, ?, ?, ?)',
                (employee_id, employee_name, department_id, 0),
            )
            conn.execute(
                'INSERT INTO system_clearances '
                '(system_name, required_clearance) VALUES (?, ?)',
                (system_name, 9),
            )
            conn.execute(
                'INSERT INTO access_logs '
                '(log_id, employee_id, system_name, access_time) VALUES (?, ?, ?, ?)',
                (log_id, employee_id, system_name, access_time),
            )

            # Also change a pre-existing expected value so replaying the original
            # three rows cannot satisfy this run.
            conn.execute(
                "UPDATE employees SET name = name || ? WHERE id = 101",
                (f'_{token}',),
            )
            conn.commit()
        finally:
            conn.close()

        expected_csv_lines = expected_lines()
        actual_csv_lines = run_and_read_output()
        assert actual_csv_lines == expected_csv_lines, (
            "CSV content did not track randomized database changes.\n"
            f"Expected:\n{chr(10).join(expected_csv_lines)}\n\n"
            f"Actual:\n{chr(10).join(actual_csv_lines)}"
        )
    finally:
        for suffix in ('-wal', '-shm'):
            sidecar = DB_PATH + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)
        os.replace(backup_path, DB_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
