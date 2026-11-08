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
import uuid


def test_indexes_sql_exists_and_valid():
    """Verify the index script is valid and its indexes were executed on the real database."""
    path = "/home/user/indexes.sql"
    db_path = "/home/user/backups.db"
    assert os.path.exists(path), f"Index creation script {path} does not exist."

    with open(path, "r") as f:
        original_content = f.read()
    content = original_content.lower()

    # Preserve the original assertions.
    assert "create " in content and "index " in content, f"No CREATE INDEX statement found in {path}."
    assert "server_id" in content or "parent_id" in content, f"Index does not target 'server_id' or 'parent_id' in {path}."

    # Execute the submitted script against a clean compatible database so syntax
    # and CREATE INDEX statements are actually exercised.
    with tempfile.TemporaryDirectory() as td:
        temp_db = os.path.join(td, "index_test.db")
        conn = sqlite3.connect(temp_db)
        conn.executescript("""
            CREATE TABLE backups (
                id INTEGER PRIMARY KEY,
                server_id INTEGER,
                parent_id INTEGER,
                type TEXT,
                size_bytes INTEGER,
                created_at DATETIME
            );
        """)
        conn.executescript(original_content)

        def index_signatures(connection):
            signatures = set()
            for row in connection.execute("PRAGMA index_list('backups')"):
                name = row[1]
                cols = tuple(r[2].lower() for r in connection.execute(
                    'PRAGMA index_info("' + name.replace('"', '""') + '")'
                ) if r[2] is not None)
                if cols:
                    signatures.add(cols)
            return signatures

        scripted_signatures = index_signatures(conn)
        conn.close()

    assert any(sig[0] == "server_id" and "created_at" in sig for sig in scripted_signatures), (
        "indexes.sql must create an index beginning with server_id and including created_at."
    )
    assert any(sig[0] == "parent_id" for sig in scripted_signatures), (
        "indexes.sql must create an index on parent_id for chain traversal."
    )

    real = sqlite3.connect(db_path)
    real_signatures = index_signatures(real)
    real.close()
    for sig in scripted_signatures:
        assert sig in real_signatures, (
            f"Index {sig} from indexes.sql was not executed on {db_path}."
        )


def test_c_program_exists_and_uses_required_features():
    """Verify that the C source exists and contains SQLite recursive-CTE logic."""
    path = "/home/user/analyze_restore.c"
    assert os.path.exists(path), f"C source file {path} does not exist."
    assert os.path.isfile(path), f"C source path {path} is not a regular file."

    with open(path, "r", errors="replace") as f:
        source = f.read()

    assert re.search(r"\bsqlite3_(open|open_v2)\s*\(", source), (
        "C source does not open the SQLite database through the sqlite3 API."
    )
    assert re.search(r"\bsqlite3_(prepare_v2|exec)\s*\(", source), (
        "C source does not execute or prepare a query through the sqlite3 API."
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "C source does not contain the required Recursive CTE."
    )


def test_executable_exists():
    """Verify that the expected executable is an executable ELF linked to SQLite."""
    path = "/home/user/analyze_restore"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert os.path.isfile(path), f"Executable {path} is not a regular file."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."

    linked = subprocess.run(
        ["ldd", path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10, check=False
    )
    assert "libsqlite3" in linked.stdout.lower(), (
        f"Executable {path} is not linked against libsqlite3.\n{linked.stdout}"
    )


def test_restore_report_content():
    """Run the submitted program and verify its report against dynamic database data."""
    report_path = "/home/user/restore_report.txt"
    db_path = "/home/user/backups.db"
    source_path = "/home/user/analyze_restore.c"
    executable_path = "/home/user/analyze_restore"

    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    with tempfile.TemporaryDirectory() as td:
        saved_db = os.path.join(td, "backups.db.saved")
        rebuilt_executable = os.path.join(td, "analyze_restore.rebuilt")
        shutil.copy2(db_path, saved_db)

        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            max_id = cursor.execute("SELECT COALESCE(MAX(id), 0) FROM backups").fetchone()[0]
            base = max_id + 1000
            salt = uuid.uuid4().int
            sizes = (
                6100000000 + salt % 1000003,
                310000000 + (salt // 1000003) % 1000033,
                170000000 + (salt // 1000036000099) % 1000037,
            )
            server_id = cursor.execute(
                "SELECT id FROM servers WHERE hostname = ?", ("db-master-42",)
            ).fetchone()[0]
            cursor.executemany(
                "INSERT INTO backups(id, server_id, parent_id, type, size_bytes, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (base, server_id, None, "F", sizes[0], "2099-12-28 01:02:03"),
                    (base + 1, server_id, base, "I", sizes[1], "2099-12-29 01:02:03"),
                    (base + 2, server_id, base + 1, "I", sizes[2], "2099-12-30 01:02:03"),
                ],
            )
            conn.commit()

            query = """
                WITH RECURSIVE
                  latest_backup AS (
                    SELECT id, parent_id, size_bytes
                    FROM backups
                    WHERE server_id = (SELECT id FROM servers WHERE hostname = 'db-master-42')
                    ORDER BY created_at DESC
                    LIMIT 1
                  ),
                  chain AS (
                    SELECT id, parent_id, size_bytes
                    FROM latest_backup
                    UNION ALL
                    SELECT b.id, b.parent_id, b.size_bytes
                    FROM backups b
                    JOIN chain c ON b.id = c.parent_id
                  )
                SELECT COUNT(*), SUM(size_bytes) FROM chain;
            """
            cursor.execute(query)
            result = cursor.fetchone()
            assert result is not None, "Failed to compute backup chain from the database."
            expected_length, expected_total_size = result
            expected_content = (
                f"Server: db-master-42 | Chain Length: {expected_length} | "
                f"Total Size: {expected_total_size} bytes"
            )
            row_count_before = cursor.execute("SELECT COUNT(*) FROM backups").fetchone()[0]
            conn.close()

            # The requested artifact itself must run and create the report.
            if os.path.exists(report_path):
                os.remove(report_path)
            run = subprocess.run(
                [executable_path], cwd="/home/user", text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=15, check=False
            )
            assert run.returncode == 0, (
                f"analyze_restore exited with {run.returncode}.\n"
                f"stdout: {run.stdout}\nstderr: {run.stderr}"
            )
            assert os.path.exists(report_path), "Running analyze_restore did not create restore_report.txt."
            with open(report_path, "r") as f:
                raw_content = f.read()
            actual_content = raw_content.strip()
            assert actual_content == expected_content, (
                f"Report content mismatch.\nExpected: '{expected_content}'\nActual:   '{actual_content}'"
            )
            assert raw_content in (expected_content, expected_content + "\n"), (
                "restore_report.txt must contain only the requested single line."
            )

            check = sqlite3.connect(db_path)
            assert check.execute("SELECT COUNT(*) FROM backups").fetchone()[0] == row_count_before, (
                "The analyzer must not alter backup metadata."
            )
            check.close()

            # Independently compile the submitted source and exercise that build too,
            # preventing an unrelated executable from satisfying the behavioral check.
            build = subprocess.run(
                ["gcc", source_path, "-o", rebuilt_executable, "-lsqlite3"],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30, check=False
            )
            assert build.returncode == 0, (
                f"Submitted C source does not compile with -lsqlite3.\n{build.stderr}"
            )
            if os.path.exists(report_path):
                os.remove(report_path)
            rebuilt_run = subprocess.run(
                [rebuilt_executable], cwd="/home/user", text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=15, check=False
            )
            assert rebuilt_run.returncode == 0, (
                f"Recompiled C program exited with {rebuilt_run.returncode}.\n"
                f"stdout: {rebuilt_run.stdout}\nstderr: {rebuilt_run.stderr}"
            )
            assert os.path.exists(report_path), "Recompiled C source did not create restore_report.txt."
            with open(report_path, "r") as f:
                rebuilt_content = f.read()
            assert rebuilt_content in (expected_content, expected_content + "\n"), (
                f"Recompiled source produced an incorrect report: {rebuilt_content!r}"
            )
        finally:
            for suffix in ("-wal", "-shm", "-journal"):
                try:
                    os.remove(db_path + suffix)
                except FileNotFoundError:
                    pass
            shutil.copy2(saved_db, db_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
