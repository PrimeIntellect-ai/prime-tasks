#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
import sqlite3
import subprocess
import pytest


def test_metrics_recovered_db():
    db_path = "/home/user/metrics_recovered.db"
    assert os.path.isfile(db_path), f"Recovered database file {db_path} is missing."

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM events")
        count = cursor.fetchone()[0]

        cursor.execute("SELECT id, data FROM events ORDER BY id")
        rows = cursor.fetchall()

        cursor.execute("PRAGMA table_info(events)")
        schema = cursor.fetchall()

        cursor.execute("PRAGMA integrity_check")
        integrity = cursor.fetchone()[0]
        conn.close()
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered database is malformed or invalid: {e}")
    except sqlite3.OperationalError as e:
        pytest.fail(f"Could not query the 'events' table in recovered database: {e}")

    assert count == 5, f"Expected 5 rows in the 'events' table, but found {count}."
    assert rows == [
        (1, "event_alpha"),
        (2, "event_beta"),
        (3, "event_gamma"),
        (4, "event_delta"),
        (5, "event_epsilon"),
    ], f"Recovered event data is incorrect: {rows!r}"
    assert integrity == "ok", f"Recovered database failed integrity_check: {integrity!r}"

    simplified_schema = [(r[1], r[2].upper(), r[4], r[5]) for r in schema]
    assert simplified_schema == [
        ("id", "INTEGER", None, 1),
        ("data", "TEXT", None, 0),
        ("timestamp", "DATETIME", "CURRENT_TIMESTAMP", 0),
    ], f"Recovered events table schema is incorrect: {schema!r}"


def test_check_db_script_exists_and_works():
    script_path = "/home/user/check_db.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    result = subprocess.run(
        ["python3", script_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{script_path} failed when executed. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )

    observed = {"paths": [], "queries": [], "fetched": False}

    class FakeCursor:
        def execute(self, query, *args, **kwargs):
            observed["queries"].append(str(query))
            return self

        def fetchone(self):
            observed["fetched"] = True
            return (937,)

        def close(self):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def execute(self, query, *args, **kwargs):
            return FakeCursor().execute(query, *args, **kwargs)

        def close(self):
            pass

        def commit(self):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

    def fake_connect(path, *args, **kwargs):
        observed["paths"].append(os.fspath(path))
        return FakeConnection()

    original_connect = sqlite3.connect
    sqlite3.connect = fake_connect
    try:
        try:
            runpy.run_path(script_path, run_name="__main__")
        except SystemExit as e:
            assert e.code in (None, 0), f"{script_path} exited with status {e.code}"
    finally:
        sqlite3.connect = original_connect

    assert "/home/user/metrics_recovered.db" in observed["paths"], (
        "check_db.py did not connect to /home/user/metrics_recovered.db"
    )
    count_query = re.compile(
        r'^select\s+count\s*\(\s*\*\s*\)\s+from\s+(?:events|"events"|`events`|\[events\])\s*;?$',
        re.IGNORECASE,
    )
    assert any(count_query.match(q.strip()) for q in observed["queries"]), (
        f"check_db.py did not execute SELECT COUNT(*) FROM events; queries were {observed['queries']!r}"
    )
    assert observed["fetched"], "check_db.py executed a query but did not retrieve its result"


def test_diagnostic_report():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.isfile(report_path), f"Diagnostic report {report_path} is missing."

    with open(report_path, "r") as f:
        raw = f.read()
        lines = [line.strip() for line in raw.strip().splitlines()]

    assert len(lines) == 2, f"Expected exactly 2 lines in diagnostic report, found {len(lines)}."
    assert lines[0] == "/home/user/legacy_plugin.so", f"First line of report is incorrect: {lines[0]}"
    assert lines[1] == "5", f"Second line of report is incorrect: {lines[1]}"
    assert raw in (
        "/home/user/legacy_plugin.so\n5",
        "/home/user/legacy_plugin.so\n5\n",
    ), "Diagnostic report contains extra text or whitespace"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
