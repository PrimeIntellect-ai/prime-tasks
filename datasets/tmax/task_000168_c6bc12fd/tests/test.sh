#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid

import pytest
import requests

RECOVERED = "/home/user/recovered.db"
EXPECTED_METADATA = "frame_data"
BUG_METADATA = "frame_data_with_an_unescaped_single_quote's_here"
BUG_SQL = "INSERT INTO frames (timestamp, metadata) VALUES (4.71, 'frame_data_with_an_unescaped_single_quote's_here')"


def test_recovered_db_exists_and_valid():
    assert os.path.exists(RECOVERED), f"Recovered database not found at {RECOVERED}"
    assert os.path.isfile(RECOVERED), "Recovered database is not a regular file"
    assert not os.path.islink(RECOVERED), "Recovered database must be an independent recovered file"
    if os.path.exists("/app/db/indexer.db"):
        assert not os.path.samefile(RECOVERED, "/app/db/indexer.db"), "Recovered database still aliases the damaged source"

    with open(RECOVERED, "rb") as f:
        assert f.read(16) == b"SQLite format 3\x00", "Recovered file is not an SQLite database"

    conn = sqlite3.connect(f"file:{RECOVERED}?mode=ro", uri=True)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        table = conn.execute(
            "SELECT type, sql FROM sqlite_master WHERE name='frames'"
        ).fetchone()
        assert table is not None and table[0] == "table", "frames table is missing"

        columns = conn.execute("PRAGMA table_info(frames)").fetchall()
        assert [c[1] for c in columns] == ["id", "timestamp", "metadata"]
        assert columns[0][5] == 1, "frames.id is not the primary key"

        rows = conn.execute(
            "SELECT id, timestamp, metadata FROM frames ORDER BY id"
        ).fetchall()
        assert len(rows) == 142, f"Expected 142 recovered rows, found {len(rows)}"
        for i, row in enumerate(rows, 1):
            assert row[0] == i, f"Missing or incorrect recovered frame id {i}"
            assert row[1] == pytest.approx(i * 0.033), f"Incorrect timestamp for frame {i}"
            assert row[2] == EXPECTED_METADATA, f"Incorrect metadata for frame {i}"
    finally:
        conn.close()


def test_mre_script():
    mre_path = "/home/user/mre.py"
    assert os.path.exists(mre_path), f"MRE script not found at {mre_path}"

    test_db_path = "/home/user/test.db"
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(test_db_path + suffix)
        except FileNotFoundError:
            pass

    hook_dir = tempfile.mkdtemp(prefix="mre_hook_")
    trace_path = f"/tmp/mre_trace_{uuid.uuid4().hex}.jsonl"
    hook = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("MRE_SQL_TRACE")

def _record(data):
    if _trace_path:
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(data, default=repr) + "\n")

class TracedCursor:
    def __init__(self, cursor):
        self._cursor = cursor
    def execute(self, sql, parameters=None):
        event = {"event": "execute", "sql": sql, "parameters": parameters}
        _record(event)
        try:
            if parameters is None:
                result = self._cursor.execute(sql)
            else:
                result = self._cursor.execute(sql, parameters)
        except Exception as exc:
            _record({"event": "error", "sql": sql, "type": type(exc).__name__, "message": str(exc)})
            raise
        return self if result is self._cursor else result
    def executemany(self, sql, seq):
        _record({"event": "executemany", "sql": sql})
        return self._cursor.executemany(sql, seq)
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class TracedConnection:
    def __init__(self, connection):
        self._connection = connection
    def cursor(self, *args, **kwargs):
        return TracedCursor(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, parameters=None):
        cur = self.cursor()
        return cur.execute(sql, parameters)
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    database = args[0] if args else kwargs.get("database")
    _record({"event": "connect", "database": str(database)})
    return TracedConnection(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    env = os.environ.copy()
    env["MRE_SQL_TRACE"] = trace_path
    env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
    try:
        result = subprocess.run(
            [sys.executable, mre_path],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )

        assert os.path.exists(test_db_path), f"MRE script did not create {test_db_path}"
        output = result.stdout.lower() + result.stderr.lower()
        assert "error" in output or "exception" in output or result.returncode != 0, \
            "MRE script did not seem to reproduce an error."
        assert result.returncode == 0, "MRE must catch and print the original exception"
        assert "near \"s\": syntax error" in output or "near 's': syntax error" in output, \
            f"MRE did not print the original SQLite syntax error: {output!r}"

        assert os.path.exists(trace_path), "MRE did not perform any instrumented SQLite operations"
        with open(trace_path, encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]

        connections = [e for e in events if e.get("event") == "connect"]
        assert any(os.path.abspath(e["database"]) == test_db_path for e in connections), \
            "MRE did not connect to /home/user/test.db"
        assert any(e.get("event") == "execute" and e.get("sql") == BUG_SQL for e in events), \
            "MRE did not execute the exact malformed INSERT from the crash"
        assert any(
            e.get("event") == "error"
            and e.get("sql") == BUG_SQL
            and e.get("type") == "OperationalError"
            and 'near "s": syntax error' in e.get("message", "")
            for e in events
        ), "The exact malformed INSERT did not genuinely raise the original OperationalError"

        conn = sqlite3.connect(test_db_path)
        try:
            columns = conn.execute("PRAGMA table_info(frames)").fetchall()
            assert [c[1] for c in columns] == ["id", "timestamp", "metadata"], \
                "MRE did not create the fresh frames schema"
            assert conn.execute("SELECT COUNT(*) FROM frames").fetchone()[0] == 0, \
                "The failing INSERT unexpectedly added a row"
        finally:
            conn.close()
    finally:
        shutil.rmtree(hook_dir, ignore_errors=True)
        try:
            os.remove(trace_path)
        except FileNotFoundError:
            pass


def test_server_source_uses_recovered_db_and_fixes_insert(tmp_path):
    server_path = "/app/src/server.py"
    assert os.path.isfile(server_path), "Server source is missing"

    spec = importlib.util.spec_from_file_location("verified_server", server_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert getattr(module, "DB_PATH", None) == RECOVERED, \
        "server.py does not point to /home/user/recovered.db"
    assert callable(getattr(module, "process_video", None)), "process_video is missing"

    test_copy = tmp_path / "process_video.db"
    shutil.copy2(RECOVERED, test_copy)
    module.DB_PATH = str(test_copy)
    module.process_video("/app/crash_evidence.mp4")

    conn = sqlite3.connect(test_copy)
    try:
        assert conn.execute("SELECT COUNT(*) FROM frames").fetchone()[0] == 143, \
            "Fixed process_video did not insert a frame"
        row = conn.execute(
            "SELECT timestamp, metadata FROM frames ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row[0] == pytest.approx(4.71)
        assert row[1] == BUG_METADATA, \
            "The fixed query did not safely preserve the apostrophe-containing metadata"
    finally:
        conn.close()


def test_service_health():
    url = "http://127.0.0.1:8080/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def test_service_frames_count():
    url = "http://127.0.0.1:8080/api/frames/count"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("count") == 142, f"Expected {{'count': 142}}, got {data}"

    sentinel_id = 1000000
    conn = sqlite3.connect(RECOVERED)
    try:
        conn.execute(
            "INSERT INTO frames(id, timestamp, metadata) VALUES (?, ?, ?)",
            (sentinel_id, 999.0, "verifier_live_database_probe"),
        )
        conn.commit()
        changed = requests.get(url, timeout=5)
        assert changed.status_code == 200
        assert changed.json().get("count") == 143, \
            "Count endpoint is hardcoded or is not reading the recovered database"
    finally:
        conn.execute("DELETE FROM frames WHERE id = ?", (sentinel_id,))
        conn.commit()
        conn.close()

    restored = requests.get(url, timeout=5)
    assert restored.status_code == 200
    assert restored.json().get("count") == 142
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
