#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile

VIOLATIONS_FILE = '/home/user/violations.txt'
SCRIPT_PATH = '/home/user/find_violations.py'
DB_PATH = '/home/user/audit.db'


def get_expected_violations():
    """Derive expected violations directly from the current database."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    try:
        query = """
            SELECT DISTINCT u.id
            FROM t_usr u
            JOIN t_prm p ON u.id = p.usr_id
            JOIN t_ast a ON p.ast_id = a.id
            WHERE a.class = 'RESTRICTED'
              AND u.dept != a.owner_dept
              AND u.rl != 'AUDITOR'
            ORDER BY u.id ASC
        """
        return [str(row[0]) for row in conn.execute(query).fetchall()]
    finally:
        conn.close()


def get_actual_violations():
    with open(VIOLATIONS_FILE, 'r') as f:
        lines = f.read().splitlines()
    return [line.strip() for line in lines if line.strip()]


def run_submission():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def test_violations_file_exists():
    """Verify that the violations.txt file was created."""
    assert os.path.isfile(VIOLATIONS_FILE), f"The output file {VIOLATIONS_FILE} was not created."


def test_violations_content():
    """Verify that the existing violations.txt contains the correct IDs."""
    expected = get_expected_violations()
    actual = get_actual_violations()
    assert actual == expected, f"Expected violations {expected}, but found {actual} in {VIOLATIONS_FILE}."


def test_script_exists_executes_and_uses_database():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."

    # Execute the submitted artifact against the original database.
    expected = get_expected_violations()
    run_submission()
    assert os.path.isfile(VIOLATIONS_FILE), f"The script did not create {VIOLATIONS_FILE}."
    actual = get_actual_violations()
    assert actual == expected, f"After executing the script, expected {expected}, but found {actual}."

    # Back up the database and output, then add a newly derived violation. This
    # ensures the script computes results rather than merely writing fixed IDs.
    temp_dir = tempfile.mkdtemp(prefix='violations_verifier_')
    db_backup = os.path.join(temp_dir, 'audit.db')
    output_backup = os.path.join(temp_dir, 'violations.txt')

    source = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(db_backup)
    try:
        source.backup(backup)
    finally:
        backup.close()
        source.close()
    shutil.copy2(VIOLATIONS_FILE, output_backup)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            restricted = conn.execute(
                "SELECT id, owner_dept FROM t_ast WHERE class = 'RESTRICTED' ORDER BY id LIMIT 1"
            ).fetchone()
            assert restricted is not None, "No RESTRICTED asset is available for the execution test."
            asset_id, owner_dept = restricted

            other_dept = conn.execute(
                "SELECT id FROM t_dpt WHERE id != ? ORDER BY id LIMIT 1",
                (owner_dept,),
            ).fetchone()
            assert other_dept is not None, "No non-owner department is available for the execution test."

            new_user_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM t_usr").fetchone()[0]
            conn.execute(
                "INSERT INTO t_usr (id, nm, dept, rl) VALUES (?, ?, ?, ?)",
                (new_user_id, 'Verifier Dynamic User', other_dept[0], 'STAFF'),
            )
            conn.execute(
                "INSERT INTO t_prm (usr_id, ast_id, lvl) VALUES (?, ?, ?)",
                (new_user_id, asset_id, 'READ'),
            )
            conn.commit()
        finally:
            conn.close()

        dynamic_expected = get_expected_violations()
        assert str(new_user_id) in dynamic_expected
        run_submission()
        dynamic_actual = get_actual_violations()
        assert dynamic_actual == dynamic_expected, (
            f"On the modified database, expected {dynamic_expected}, but found {dynamic_actual}."
        )
    finally:
        for suffix in ('-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(output_backup, VIOLATIONS_FILE)
        shutil.rmtree(temp_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
