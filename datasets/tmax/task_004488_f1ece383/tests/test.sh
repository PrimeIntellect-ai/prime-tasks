#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
import urllib.parse

DB_PATH = "/home/user/artifacts.db"
SCRIPT_PATH = "/home/user/migrate.sh"


def test_db_file_exists():
    """Check if the SQLite database file exists."""
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"


def test_migration_script_exists_and_is_bash():
    """Require the requested migration artifact and valid Bash syntax."""
    assert os.path.isfile(SCRIPT_PATH), f"Migration script missing at {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, "Migration script is empty"
    result = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Migration script has invalid Bash syntax: {result.stderr}"


def test_v2_artifacts_table_exists():
    """Check if the v2_artifacts table exists in the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='v2_artifacts';")
    result = cursor.fetchone()
    conn.close()
    assert result is not None, "Table 'v2_artifacts' does not exist in the database. Did you create it?"


def test_v2_artifacts_schema():
    """Check if the v2_artifacts table has the correct schema."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(v2_artifacts);")
    columns = cursor.fetchall()
    conn.close()

    column_names = [col[1] for col in columns]
    expected_columns = ["id", "project", "version", "filename", "branch", "commit_hash"]

    for expected in expected_columns:
        assert expected in column_names, f"Column '{expected}' is missing from v2_artifacts table."


def test_v2_artifacts_data():
    """Check if the v2_artifacts table contains the correctly migrated data."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, project, version, filename, branch, commit_hash FROM v2_artifacts ORDER BY id;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        (1, 'frontend', 'v1.0.0', 'bundle.js', 'main', 'a3f29cd'),
        (2, 'backend', 'v2.3.1', 'server.bin', 'staging', 'b83912f'),
        (3, 'auth-service', 'v0.9.5', 'auth-linux-amd64', 'hotfix-1', 'c123456')
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in v2_artifacts, found {len(rows)}."
    for row, expected in zip(rows, expected_rows):
        assert row == expected, f"Row mismatch in v2_artifacts: expected {expected}, got {row}."


def test_zz_migration_script_processes_fresh_dynamic_rows():
    """Execute the submitted script on unpredictable legacy rows and verify its migration logic."""
    fd, backup_path = tempfile.mkstemp(prefix="artifacts-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    expected_rows = []
    try:
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.remove(DB_PATH)

        conn = sqlite3.connect(DB_PATH)
        conn.execute("CREATE TABLE v1_artifacts (id INTEGER PRIMARY KEY, webhook_url TEXT)")

        for index in range(3):
            row_id = 41 + index * 17
            token = secrets.token_hex(6)
            project = f"project-{token[:6]}"
            version = f"v{index + 3}.{int(token[0], 16)}.{int(token[1], 16)}"
            filename = f"artifact-{token[6:]}.bin"
            branch = f"feature-{secrets.token_hex(4)}"
            commit_hash = secrets.token_hex(10)
            metadata = f"branch={branch},commit={commit_hash}"
            encoded_meta = urllib.parse.quote(
                base64.b64encode(metadata.encode()).decode(), safe=""
            )
            url = (
                f"http://build.internal/api/v1/artifacts/{project}/{version}"
                f"?file={filename}&encoded_meta={encoded_meta}"
            )
            conn.execute(
                "INSERT INTO v1_artifacts (id, webhook_url) VALUES (?, ?)",
                (row_id, url),
            )
            expected_rows.append(
                (row_id, project, version, filename, branch, commit_hash)
            )
        conn.commit()
        conn.close()

        result = subprocess.run(
            ["bash", SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Migration script failed on fresh legacy data (exit {result.returncode}). "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        conn = sqlite3.connect(DB_PATH)
        try:
            table = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='v2_artifacts'"
            ).fetchone()
            assert table is not None, "Script did not create v2_artifacts on a fresh database"

            columns = [row[1] for row in conn.execute("PRAGMA table_info(v2_artifacts)")]
            expected_columns = ["id", "project", "version", "filename", "branch", "commit_hash"]
            for expected in expected_columns:
                assert expected in columns, f"Column '{expected}' is missing after executing the script"

            rows = conn.execute(
                "SELECT id, project, version, filename, branch, commit_hash "
                "FROM v2_artifacts ORDER BY id"
            ).fetchall()
            assert rows == expected_rows, (
                f"Script did not parse and migrate dynamic webhook rows correctly: "
                f"expected {expected_rows}, got {rows}"
            )
        finally:
            conn.close()
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.move(backup_path, DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
