#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess

DB_PATH = "/home/user/backups.db"
BAD_INDEX_FILE = "/home/user/bad_index.txt"
ANALYZE_SCRIPT = "/home/user/analyze_graph.sh"
TOP_JOBS_FILE = "/home/user/top_jobs.csv"
BACKUP_PATHS_FILE = "/home/user/backup_paths.csv"


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_bad_index_file():
    assert os.path.exists(BAD_INDEX_FILE), f"File {BAD_INDEX_FILE} is missing."
    with open(BAD_INDEX_FILE, "r") as f:
        content = f.read().strip()
    assert content == "idx_deps_child_only", f"Expected 'idx_deps_child_only' in {BAD_INDEX_FILE}, got '{content}'"


def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_deps_child_only';")
    assert cursor.fetchone() is None, "The bad index 'idx_deps_child_only' was not dropped."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_deps_optimal';")
    assert cursor.fetchone() is not None, "The optimal index 'idx_deps_optimal' was not created."

    cursor.execute("PRAGMA index_info('idx_deps_optimal');")
    index_info = cursor.fetchall()
    columns = [row[2] for row in index_info]
    assert columns == ['parent_id', 'child_id'], f"Index 'idx_deps_optimal' should be on (parent_id, child_id), but got {columns}"
    conn.close()


def test_analyze_script_executable_and_sql_constructs():
    assert os.path.isfile(ANALYZE_SCRIPT), f"Script {ANALYZE_SCRIPT} is missing or is not a regular file."
    assert os.access(ANALYZE_SCRIPT, os.X_OK), f"Script {ANALYZE_SCRIPT} is not executable."
    with open(ANALYZE_SCRIPT, "r") as f:
        script = f.read()
    assert script.startswith("#!") and "bash" in script.splitlines()[0], "analyze_graph.sh must be a Bash script."
    assert re.search(r"\bsqlite3\b", script, re.I), "analyze_graph.sh must use sqlite3."
    assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", script, re.I | re.S), "analyze_graph.sh must use RANK() OVER (...)."
    assert re.search(r"\bWITH\s+RECURSIVE\b", script, re.I), "The submitted graph-analysis script must contain the required Recursive CTE."


def test_top_jobs_csv():
    assert os.path.exists(TOP_JOBS_FILE), f"File {TOP_JOBS_FILE} is missing."
    lines = nonempty_lines(TOP_JOBS_FILE)
    expected_lines = [
        "1,SystemDB,2",
        "1,AppDB,2",
        "3,UserDB,1"
    ]
    assert sorted(lines) == sorted(expected_lines), f"Expected {expected_lines} in {TOP_JOBS_FILE}, got {lines}"


def test_backup_paths_csv():
    assert os.path.exists(BACKUP_PATHS_FILE), f"File {BACKUP_PATHS_FILE} is missing."
    lines = nonempty_lines(BACKUP_PATHS_FILE)
    expected_lines = [
        "SystemDB",
        "SystemDB->AppDB",
        "SystemDB->LogDB",
        "SystemDB->AppDB->UserDB",
        "SystemDB->AppDB->PaymentDB",
        "SystemDB->AppDB->UserDB->AnalyticsDB"
    ]
    assert sorted(lines) == sorted(expected_lines), f"Expected {expected_lines} in {BACKUP_PATHS_FILE}, got {lines}"


def test_zz_script_executes_real_window_and_recursive_queries_on_changed_data(tmp_path):
    db_backup = tmp_path / "backups.db"
    shutil.copy2(DB_PATH, db_backup)
    saved_outputs = {}
    for path in (TOP_JOBS_FILE, BACKUP_PATHS_FILE):
        saved_outputs[path] = open(path, "rb").read() if os.path.exists(path) else None

    sqlite_bin = shutil.which("sqlite3")
    assert sqlite_bin == "/usr/bin/sqlite3", f"Unexpected sqlite3 location: {sqlite_bin}"
    real_sqlite = "/usr/bin/sqlite3.verifier-real"
    sql_log = tmp_path / "sqlite.log"

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.executemany("INSERT INTO jobs(id, name) VALUES (?, ?)", [
            (101, "VerifierProbeRoot"), (102, "VerifierLeafA"),
            (103, "VerifierLeafB"), (104, "VerifierLeafC"),
            (105, "VerifierLeafD"), (106, "VerifierPathA"),
            (107, "VerifierPathB")
        ])
        conn.executemany("INSERT INTO deps(parent_id, child_id) VALUES (?, ?)", [
            (101, 102), (101, 103), (101, 104), (101, 105),
            (1, 106), (106, 107)
        ])
        conn.commit()

        expected_top = [",".join(map(str, row)) for row in conn.execute("""
            WITH counts AS (
              SELECT j.id, j.name, COUNT(d.child_id) AS child_count
              FROM jobs AS j LEFT JOIN deps AS d ON d.parent_id = j.id
              GROUP BY j.id, j.name
            ), ranked AS (
              SELECT RANK() OVER (ORDER BY child_count DESC) AS rnk,
                     name, child_count
              FROM counts
            )
            SELECT rnk, name, child_count
            FROM ranked
            ORDER BY rnk, name
            LIMIT 3
        """)]
        expected_paths = [row[0] for row in conn.execute("""
            WITH RECURSIVE paths(id, path) AS (
              SELECT id, name FROM jobs WHERE name = 'SystemDB'
              UNION ALL
              SELECT j.id, paths.path || '->' || j.name
              FROM paths
              JOIN deps d ON d.parent_id = paths.id
              JOIN jobs j ON j.id = d.child_id
            )
            SELECT path FROM paths
        """)]
        conn.close()

        for path in (TOP_JOBS_FILE, BACKUP_PATHS_FILE):
            if os.path.exists(path):
                os.remove(path)

        os.replace(sqlite_bin, real_sqlite)
        wrapper = f'''#!/bin/bash
set -e
tmp=$(mktemp)
cat > "$tmp"
{{ printf '%s\\n' "$*"; cat "$tmp"; printf '\\n'; }} >> {str(sql_log)!r}
exec {real_sqlite} "$@" < "$tmp"
'''
        with open(sqlite_bin, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_bin, 0o755)

        result = subprocess.run(
            [ANALYZE_SCRIPT], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, f"analyze_graph.sh failed: {result.stderr}"
        assert os.path.exists(TOP_JOBS_FILE), "analyze_graph.sh did not generate top_jobs.csv."
        assert os.path.exists(BACKUP_PATHS_FILE), "Graph analysis did not regenerate backup_paths.csv."
        assert sorted(nonempty_lines(TOP_JOBS_FILE)) == sorted(expected_top), \
            f"top_jobs.csv was not computed from the changed database; expected {expected_top}"
        assert sorted(nonempty_lines(BACKUP_PATHS_FILE)) == sorted(expected_paths), \
            "backup_paths.csv was not computed from the changed graph."

        logged_sql = sql_log.read_text() if sql_log.exists() else ""
        assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", logged_sql, re.I | re.S), \
            "The SQL actually sent to sqlite3 did not use RANK() OVER (...)."
        assert re.search(r"\bWITH\s+RECURSIVE\b", logged_sql, re.I), \
            "The SQL actually sent to sqlite3 did not use a Recursive CTE."
    finally:
        if os.path.exists(real_sqlite):
            if os.path.exists(sqlite_bin):
                os.remove(sqlite_bin)
            os.replace(real_sqlite, sqlite_bin)
        shutil.copy2(db_backup, DB_PATH)
        for path, data in saved_outputs.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
