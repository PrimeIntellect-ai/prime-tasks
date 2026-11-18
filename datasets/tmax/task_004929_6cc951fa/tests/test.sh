#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import os
import sqlite3

_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    trace_path = os.environ.get("BACKUP_SQL_TRACE")
    if trace_path:
        def record(statement):
            try:
                with open(trace_path, "a", encoding="utf-8") as f:
                    f.write(statement.replace("\n", " ") + "\n")
            except OSError:
                pass
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _connect
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
from collections import defaultdict

import pytest

DB_PATH = "/home/user/backup_metadata.db"
REPORT_PATH = "/home/user/backup_report.json"
SCRIPT_PATH = "/home/user/analyze_backups.py"
TRACE_PATH = "/tmp/analyze_backups_sql.trace"


def get_expected_results():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file missing at {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Compute critical backup id
    c.execute("""
        SELECT parent_id, COUNT(*) as children
        FROM backups
        WHERE parent_id IS NOT NULL
        GROUP BY parent_id
        ORDER BY children DESC, parent_id ASC
        LIMIT 1
    """)
    row = c.fetchone()
    critical_backup_id = row[0] if row else None

    # Compute anomalies
    c.execute("""
        SELECT id, cluster_id, duration_sec, timestamp
        FROM backups
        ORDER BY cluster_id, timestamp
    """)
    rows = c.fetchall()

    clusters = defaultdict(list)
    for r in rows:
        clusters[r[1]].append(r)

    anomalies = []
    for cluster, backups in clusters.items():
        for i in range(3, len(backups)):
            prev3 = backups[i-3:i]
            avg = sum(b[2] for b in prev3) / 3.0
            if backups[i][2] > 1.5 * avg:
                anomalies.append({
                    "backup_id": backups[i][0],
                    "cluster_id": cluster,
                    "duration": backups[i][2],
                    "moving_avg": round(avg, 2)
                })

    anomalies.sort(key=lambda x: x["backup_id"])
    conn.close()
    return critical_backup_id, anomalies


def assert_report_content():
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report file is not valid JSON.")

    expected_critical_id, expected_anomalies = get_expected_results()

    assert "critical_backup_id" in report, "Missing 'critical_backup_id' in report."
    assert report["critical_backup_id"] == expected_critical_id, \
        f"Expected critical_backup_id to be {expected_critical_id}, got {report['critical_backup_id']}."

    assert "anomalies" in report, "Missing 'anomalies' in report."
    assert isinstance(report["anomalies"], list), "'anomalies' should be a list."

    actual_anomalies = report["anomalies"]
    assert len(actual_anomalies) == len(expected_anomalies), \
        f"Expected {len(expected_anomalies)} anomalies, got {len(actual_anomalies)}."

    for actual, expected in zip(actual_anomalies, expected_anomalies):
        assert actual.get("backup_id") == expected["backup_id"], \
            f"Expected backup_id {expected['backup_id']}, got {actual.get('backup_id')}."
        assert actual.get("cluster_id") == expected["cluster_id"], \
            f"Expected cluster_id '{expected['cluster_id']}', got '{actual.get('cluster_id')}'."
        assert actual.get("duration") == expected["duration"], \
            f"Expected duration {expected['duration']}, got {actual.get('duration')}."
        assert actual.get("moving_avg") == expected["moving_avg"], \
            f"Expected moving_avg {expected['moving_avg']}, got {actual.get('moving_avg')}."


def assert_window_query_executed():
    assert os.path.exists(TRACE_PATH), "The script did not connect through Python's sqlite3 module."
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        statements = [line.upper() for line in f if line.strip()]

    window_queries = [
        sql for sql in statements
        if re.search(r"\bSELECT\b", sql)
        and re.search(r"\bAVG\s*\(", sql)
        and re.search(r"\bOVER\b", sql)
        and re.search(r"\bPARTITION\s+BY\b", sql)
        and re.search(r"\bORDER\s+BY\b", sql)
        and "DURATION_SEC" in sql
        and re.search(r"\b3\s+PRECEDING\b", sql)
        and (re.search(r"\b1\s+PRECEDING\b", sql) or "EXCLUDE CURRENT ROW" in sql)
    ]
    assert window_queries, "The script did not execute the required previous-three-rows SQL window query."


def run_script():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["BACKUP_SQL_TRACE"] = TRACE_PATH
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_backups.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_window_query_executed()


def install_rows(rows):
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM backups")
        conn.executemany("INSERT INTO backups VALUES (?,?,?,?,?,?)", rows)
        conn.commit()
    finally:
        conn.close()


@pytest.fixture(scope="session", autouse=True)
def restore_database_after_tests():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    fd, saved_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, saved_path)
    try:
        yield
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(saved_path, DB_PATH)
        os.remove(saved_path)


@pytest.fixture(scope="module")
def original_report():
    assert os.path.exists(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} is not a regular file"
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    compile(source, SCRIPT_PATH, "exec")
    run_script()


def test_report_exists(original_report):
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"


def test_report_content(original_report):
    assert_report_content()


DYNAMIC_CASES = [
    [
        (101, "alpha", "full", None, 30, "2024-01-01 00:00:00"),
        (102, "alpha", "incremental", 101, 30, "2024-01-02 00:00:00"),
        (103, "alpha", "incremental", 101, 30, "2024-01-03 00:00:00"),
        (104, "alpha", "incremental", 101, 46, "2024-01-04 00:00:00"),
        (105, "alpha", "incremental", 101, 30, "2024-01-05 00:00:00"),
        (201, "beta", "full", None, 8, "2024-02-01 00:00:00"),
        (202, "beta", "incremental", 201, 10, "2024-02-02 00:00:00"),
        (203, "beta", "incremental", 201, 12, "2024-02-03 00:00:00"),
        (204, "beta", "incremental", 202, 16, "2024-02-04 00:00:00"),
        (205, "beta", "incremental", 203, 15, "2024-02-05 00:00:00"),
    ],
    [
        (501, "gamma", "full", None, 100, "2025-03-01 00:00:00"),
        (502, "gamma", "incremental", 501, 10, "2025-03-02 00:00:00"),
        (503, "gamma", "incremental", 501, 10, "2025-03-03 00:00:00"),
        (504, "gamma", "incremental", 501, 60, "2025-03-04 00:00:00"),
        (505, "gamma", "incremental", 501, 40, "2025-03-05 00:00:00"),
        (506, "gamma", "incremental", 501, 80, "2025-03-06 00:00:00"),
        (601, "delta", "full", None, 20, "2025-04-01 00:00:00"),
        (602, "delta", "incremental", 601, 20, "2025-04-02 00:00:00"),
        (603, "delta", "incremental", 602, 20, "2025-04-03 00:00:00"),
        (604, "delta", "incremental", 603, 20, "2025-04-04 00:00:00"),
    ],
]


@pytest.mark.parametrize("rows", DYNAMIC_CASES)
def test_pipeline_on_changed_database(original_report, rows):
    install_rows(rows)
    run_script()
    assert_report_content()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
