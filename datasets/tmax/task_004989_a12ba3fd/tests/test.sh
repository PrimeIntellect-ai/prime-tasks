#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

DB_PATH = "/home/user/backups_meta.db"
OPTIMIZE_SQL_PATH = "/home/user/optimize.sql"
ANALYZE_PY_PATH = "/home/user/analyze_backups.py"
REPORT_JSON_PATH = "/home/user/report.json"
EXPECTED_KEYS = {"hostname", "crossing_timestamp", "running_total_bytes"}


def index_columns(conn):
    result = []
    for row in conn.execute("PRAGMA index_list('backups')"):
        name = row[1]
        escaped = name.replace("'", "''")
        columns = [info[2] for info in conn.execute(f"PRAGMA index_info('{escaped}')")]
        result.append((name, columns))
    return result


def has_required_composite_index(conn):
    for _, columns in index_columns(conn):
        if {"status", "server_id", "timestamp"}.issubset(columns):
            if columns.index("server_id") < columns.index("timestamp"):
                return True
    return False


def expected_original_data():
    random.seed(42)
    servers = [
        (1, "app-server-eu", "eu-west-1"),
        (2, "db-server-us", "us-east-1"),
        (3, "cache-server-ap", "ap-south-1"),
    ]
    start_time = datetime(2023, 10, 1)
    backups = []
    backup_id = 1
    for server_id, _, _ in servers:
        current_time = start_time
        for _ in range(20):
            status = "SUCCESS" if random.random() < 0.9 else "FAILED"
            size = random.randint(20000000, 100000000)
            backups.append((backup_id, server_id, current_time.isoformat() + "Z", size, status))
            backup_id += 1
            current_time += timedelta(hours=12)
    random.shuffle(backups)
    return servers, sorted(backups)


def test_optimize_sql_exists():
    assert os.path.exists(OPTIMIZE_SQL_PATH), f"{OPTIMIZE_SQL_PATH} does not exist."
    assert os.path.isfile(OPTIMIZE_SQL_PATH), f"{OPTIMIZE_SQL_PATH} is not a file."
    assert os.path.getsize(OPTIMIZE_SQL_PATH) > 0, f"{OPTIMIZE_SQL_PATH} is empty."


def test_analyze_script_exists():
    assert os.path.exists(ANALYZE_PY_PATH), f"{ANALYZE_PY_PATH} does not exist."
    assert os.path.isfile(ANALYZE_PY_PATH), f"{ANALYZE_PY_PATH} is not a file."


def test_database_was_not_replaced_or_emptied():
    expected_servers, expected_backups = expected_original_data()
    conn = sqlite3.connect(DB_PATH)
    try:
        actual_servers = conn.execute(
            "SELECT id, hostname, region FROM servers ORDER BY id"
        ).fetchall()
        actual_backups = conn.execute(
            "SELECT id, server_id, timestamp, size_bytes, status FROM backups ORDER BY id"
        ).fetchall()
    finally:
        conn.close()
    assert actual_servers == expected_servers, "The supplied servers data was modified."
    assert actual_backups == expected_backups, "The supplied backups data was modified or emptied."


def test_database_indexes_applied():
    """Preserve the original assertion that an applied index includes server_id."""
    conn = sqlite3.connect(DB_PATH)
    try:
        found_valid_index = any("server_id" in cols for _, cols in index_columns(conn))
    finally:
        conn.close()
    assert found_valid_index, "No index found on backups that includes server_id."


def test_optimization_script_creates_covering_access_index():
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "fresh.db")
        conn = sqlite3.connect(db)
        try:
            conn.executescript("""
                CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);
                CREATE TABLE backups (
                    id INTEGER PRIMARY KEY,
                    server_id INTEGER,
                    timestamp TEXT,
                    size_bytes INTEGER,
                    status TEXT
                );
            """)
            sql = open(OPTIMIZE_SQL_PATH, encoding="utf-8").read()
            conn.executescript(sql)
            assert has_required_composite_index(conn), (
                "optimize.sql must create a backups index covering status, server_id, "
                "and timestamp, with server_id before timestamp for partition ordering."
            )
        finally:
            conn.close()


def load_and_validate_report(path):
    assert os.path.exists(path), f"{path} does not exist."
    try:
        with open(path, encoding="utf-8") as handle:
            report = json.load(handle)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path} is not valid JSON: {exc}")
    assert isinstance(report, list), "The JSON report must be a list of objects."
    for i, row in enumerate(report):
        assert isinstance(row, dict), f"Item at index {i} is not a JSON object."
        assert set(row) == EXPECTED_KEYS, f"Item at index {i} must have exactly the required keys."
        assert isinstance(row["hostname"], str)
        assert isinstance(row["crossing_timestamp"], str)
        assert isinstance(row["running_total_bytes"], int)
    return report


def derive_truth(conn):
    rows = conn.execute("""
        WITH running AS (
            SELECT b.server_id, b.timestamp,
                   SUM(b.size_bytes) OVER (
                       PARTITION BY b.server_id ORDER BY b.timestamp ASC
                   ) AS running_total
            FROM backups b
            WHERE b.status = 'SUCCESS'
        ), thresholds AS (
            SELECT s.hostname, r.timestamp AS crossing_timestamp,
                   r.running_total AS running_total_bytes,
                   ROW_NUMBER() OVER (
                       PARTITION BY r.server_id ORDER BY r.timestamp ASC
                   ) AS rn
            FROM running r
            JOIN servers s ON r.server_id = s.id
            WHERE r.running_total > 500000000
        )
        SELECT hostname, crossing_timestamp, running_total_bytes
        FROM thresholds WHERE rn = 1 ORDER BY hostname ASC
    """).fetchall()
    return [dict(zip(("hostname", "crossing_timestamp", "running_total_bytes"), row)) for row in rows]


def test_report_json_correctness():
    """Preserve the original report assertion against the protected supplied database."""
    student_report = load_and_validate_report(REPORT_JSON_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        expected_report = derive_truth(conn)
    finally:
        conn.close()
    assert student_report == expected_report


def make_challenge_database(path, seed):
    rng = random.Random(seed)
    token = f"{rng.getrandbits(48):012x}"
    hostnames = [f"alpha-{token}", f"kappa-{token}", f"omega-{token}", f"zeta-{token}"]
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);
        CREATE TABLE backups (
            id INTEGER PRIMARY KEY,
            server_id INTEGER,
            timestamp TEXT,
            size_bytes INTEGER,
            status TEXT
        );
    """)
    conn.executemany(
        "INSERT INTO servers VALUES (?, ?, ?)",
        [(i + 1, hostname, f"r-{i}") for i, hostname in enumerate(hostnames)],
    )
    rows = []
    backup_id = 1
    base = datetime(2025, 1, 1)
    for server_id in range(1, 5):
        for n in range(13):
            timestamp = (base + timedelta(hours=7 * n + server_id)).isoformat() + "Z"
            if server_id == 4:
                size = rng.randint(5000000, 12000000)
            else:
                size = rng.randint(45000000, 105000000)
            status = "FAILED" if (n + server_id) % 5 == 0 else "SUCCESS"
            rows.append((backup_id, server_id, timestamp, size, status))
            backup_id += 1
    rng.shuffle(rows)
    conn.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", rows)
    conn.commit()
    return conn


def normalize_sql(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return " ".join(sql.upper().split())


def run_instrumented_analyzer(trace_path):
    instrument_dir = tempfile.mkdtemp(prefix="sqlite_trace_")
    sitecustomize = os.path.join(instrument_dir, "sitecustomize.py")
    with open(sitecustomize, "w", encoding="utf-8") as handle:
        handle.write(r'''
import os
import sqlite3
_original_connect = sqlite3.connect

def _connect(*args, **kwargs):
    connection = _original_connect(*args, **kwargs)
    trace_file = os.environ.get("ANALYZER_SQL_TRACE")
    if trace_file:
        def _trace(statement):
            with open(trace_file, "a", encoding="utf-8") as output:
                output.write(statement.replace("\x00", "") + "\n\x1e\n")
        connection.set_trace_callback(_trace)
    return connection
sqlite3.connect = _connect
''')
    env = os.environ.copy()
    env["ANALYZER_SQL_TRACE"] = trace_path
    env["PYTHONPATH"] = instrument_dir + os.pathsep + env.get("PYTHONPATH", "")
    try:
        result = subprocess.run(
            ["python3", ANALYZE_PY_PATH], cwd="/home/user", env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
    finally:
        shutil.rmtree(instrument_dir, ignore_errors=True)
    assert result.returncode == 0, f"analyze_backups.py failed:\n{result.stderr}"


def test_analyzer_executes_one_window_query_on_unseen_data():
    with tempfile.TemporaryDirectory() as td:
        saved_db = os.path.join(td, "saved.db")
        original = sqlite3.connect(DB_PATH)
        backup = sqlite3.connect(saved_db)
        try:
            original.backup(backup)
        finally:
            backup.close()
            original.close()
        old_report = None
        if os.path.exists(REPORT_JSON_PATH):
            with open(REPORT_JSON_PATH, "rb") as handle:
                old_report = handle.read()
        try:
            for suffix in ("", "-wal", "-shm"):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            challenge = make_challenge_database(DB_PATH, int.from_bytes(os.urandom(16), "big"))
            sql = open(OPTIMIZE_SQL_PATH, encoding="utf-8").read()
            challenge.executescript(sql)
            assert has_required_composite_index(challenge)
            expected = derive_truth(challenge)
            challenge.close()

            if os.path.exists(REPORT_JSON_PATH):
                os.remove(REPORT_JSON_PATH)
            trace_path = os.path.join(td, "trace.log")
            run_instrumented_analyzer(trace_path)
            actual = load_and_validate_report(REPORT_JSON_PATH)
            assert actual == expected, "Analyzer output is incorrect on unseen database contents."

            assert os.path.exists(trace_path), "Analyzer did not connect to SQLite."
            trace = open(trace_path, encoding="utf-8").read().split("\n\x1e\n")
            read_queries = []
            for statement in trace:
                normalized = normalize_sql(statement)
                if re.match(r"^(SELECT|WITH)\b", normalized):
                    read_queries.append(normalized)
            assert len(read_queries) == 1, (
                f"Expected exactly one SQL query, observed {len(read_queries)}."
            )
            query = read_queries[0]
            required_patterns = {
                "a SUM window function": r"\bSUM\s*\([^)]*SIZE_BYTES[^)]*\)\s*OVER\s*\(",
                "partitioning by server_id": r"PARTITION\s+BY\s+(?:\w+\.)?SERVER_ID",
                "ordering by timestamp": r"ORDER\s+BY\s+(?:\w+\.)?TIMESTAMP",
                "SUCCESS filtering": r"\bSTATUS\b[^\n]*\bSUCCESS\b",
                "the strict threshold": r">\s*500000000",
                "the servers join": r"\bSERVERS\b",
            }
            for description, pattern in required_patterns.items():
                assert re.search(pattern, query), f"The executed query is missing {description}."
        finally:
            for suffix in ("", "-wal", "-shm"):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            shutil.copyfile(saved_db, DB_PATH)
            if old_report is None:
                try:
                    os.remove(REPORT_JSON_PATH)
                except FileNotFoundError:
                    pass
            else:
                with open(REPORT_JSON_PATH, "wb") as handle:
                    handle.write(old_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
