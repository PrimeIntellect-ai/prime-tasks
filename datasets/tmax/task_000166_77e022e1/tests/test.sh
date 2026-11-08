#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import uuid

DB_PATH = "/home/user/research.db"
LOG_PATH = "/home/user/result.log"
SCRIPT_PATH = "/home/user/organize_and_deadlock.py"
CSV_PATH = "/home/user/metadata.csv"
JSONL_PATH = "/home/user/research_data.jsonl"

with open(CSV_PATH, "rb") as f:
    ORIGINAL_CSV = f.read()
with open(JSONL_PATH, "rb") as f:
    ORIGINAL_JSONL = f.read()

INSTRUMENT_DIR = tempfile.mkdtemp(prefix="sqlite_instrument_")
EVENT_PATH = os.path.join(INSTRUMENT_DIR, "events.jsonl")

SITECUSTOMIZE = r'''
import json
import os
import sqlite3
import threading

_real_connect = sqlite3.connect
_log_path = os.environ.get("SQLITE_EVENT_LOG")
_log_lock = threading.Lock()
_next_id = 0


def _log(kind, **fields):
    if not _log_path:
        return
    record = {"kind": kind, "thread": threading.get_ident()}
    record.update(fields)
    try:
        with _log_lock:
            with open(_log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, sort_keys=True) + "\\n")
    except Exception:
        pass


_log("init")


def _record_sql(cid, sql, params, method):
    text = str(sql)
    _log("sql", connection=cid, sql=text, method=method,
         has_parameters=params is not None and params != () and params != [])


class CursorProxy:
    def __init__(self, inner, cid):
        self._inner = inner
        self._cid = cid

    def execute(self, sql, parameters=()):
        _record_sql(self._cid, sql, parameters, "execute")
        try:
            self._inner.execute(sql, parameters)
            return self
        except sqlite3.OperationalError as e:
            _log("operational_error", connection=self._cid, message=str(e), sql=str(sql))
            raise

    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        _record_sql(self._cid, sql, values, "executemany")
        try:
            self._inner.executemany(sql, values)
            return self
        except sqlite3.OperationalError as e:
            _log("operational_error", connection=self._cid, message=str(e), sql=str(sql))
            raise

    def executescript(self, sql_script):
        _record_sql(self._cid, sql_script, None, "executescript")
        try:
            self._inner.executescript(sql_script)
            return self
        except sqlite3.OperationalError as e:
            _log("operational_error", connection=self._cid, message=str(e), sql=str(sql_script))
            raise

    def __iter__(self):
        return iter(self._inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)


class ConnectionProxy:
    def __init__(self, inner, cid):
        self._inner = inner
        self._cid = cid

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs), self._cid)

    def execute(self, sql, parameters=()):
        cur = self.cursor()
        return cur.execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        cur = self.cursor()
        return cur.executemany(sql, seq_of_parameters)

    def executescript(self, sql_script):
        cur = self.cursor()
        return cur.executescript(sql_script)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)


def connect(*args, **kwargs):
    global _next_id
    timeout = kwargs.get("timeout", args[1] if len(args) > 1 else 5.0)
    database = kwargs.get("database", args[0] if args else None)
    inner = _real_connect(*args, **kwargs)
    with _log_lock:
        _next_id += 1
        cid = _next_id
    _log("connect", connection=cid, database=str(database), timeout=timeout)
    return ConnectionProxy(inner, cid)


sqlite3.connect = connect
'''

with open(os.path.join(INSTRUMENT_DIR, "sitecustomize.py"), "w", encoding="utf-8") as f:
    f.write(SITECUSTOMIZE)


def read_events():
    if not os.path.exists(EVENT_PATH):
        return []
    events = []
    with open(EVENT_PATH, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    return events


def run_script():
    for path in (DB_PATH, LOG_PATH, EVENT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["SQLITE_EVENT_LOG"] = EVENT_PATH
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=25,
        env=env,
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    return read_events()


def read_and_check_log(conn):
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"
    with open(LOG_PATH, encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {LOG_PATH}, found {len(lines)}"
    plan_line, deadlock_line = lines
    assert plan_line.startswith("PLAN:"), "First line must start with 'PLAN:'"
    assert "SEARCH" in plan_line.upper() or "SCAN" in plan_line.upper(), \
        "First line should contain the query plan details"
    assert "INDEX" in plan_line.upper(), "Query plan should indicate the use of an index"
    assert deadlock_line == "DEADLOCK_ACHIEVED", \
        "Second line must be exactly 'DEADLOCK_ACHIEVED'"

    details = [str(row[3]) for row in conn.execute(
        "EXPLAIN QUERY PLAN SELECT researchers.name, experiments.doc_data "
        "FROM experiments JOIN researchers "
        "ON experiments.researcher_id = researchers.id "
        "WHERE researchers.name = ?", ("Alice",)
    )]
    reported = plan_line[len("PLAN:"):].strip()
    assert reported in details, (
        f"Reported plan detail {reported!r} was not produced by SQLite; actual details: {details!r}"
    )
    assert any("INDEX" in detail.upper() for detail in details), \
        f"The actual query plan does not use an index: {details!r}"


def check_concurrency(events):
    init_events = [e for e in events if e.get("kind") == "init"]
    assert init_events, "No execution telemetry was produced by the submitted script"
    main_thread = init_events[0]["thread"]

    connects = [e for e in events if e.get("kind") == "connect"]
    low_timeout_ids = {
        e["connection"] for e in connects
        if isinstance(e.get("timeout"), (int, float)) and e["timeout"] <= 0.1
    }
    assert len(low_timeout_ids) >= 2, \
        "Concurrency test must use at least two sqlite3 connections with timeout <= 0.1"

    write_re = re.compile(r"^\s*(?:UPDATE|INSERT|DELETE|REPLACE)\b", re.I)
    transaction_re = re.compile(r"^\s*(?:BEGIN|UPDATE|INSERT|DELETE|REPLACE)\b", re.I)
    attempts = [
        e for e in events
        if e.get("kind") == "sql"
        and e.get("connection") in low_timeout_ids
        and transaction_re.search(e.get("sql", ""))
    ]
    worker_threads = {e["thread"] for e in attempts if e["thread"] != main_thread}
    worker_connections = {e["connection"] for e in attempts if e["thread"] != main_thread}
    assert len(worker_threads) >= 2, \
        "Transactional database work was not observed in two separate worker threads"
    assert len(worker_connections) >= 2, \
        "The worker threads did not use two separate sqlite3 connections"
    assert any(write_re.search(e.get("sql", "")) for e in attempts), \
        "No concurrent write attempt was observed"

    lock_errors = [
        e for e in events
        if e.get("kind") == "operational_error"
        and "locked" in e.get("message", "").lower()
        and e.get("thread") != main_thread
    ]
    assert lock_errors, \
        "No sqlite3.OperationalError reporting a locked database was observed in a worker thread"


def check_schema_and_index(conn):
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "researchers" in tables, "Table 'researchers' is missing in the database"
    assert "experiments" in tables, "Table 'experiments' is missing in the database"

    researcher_cols = [(r[1], r[2], r[5]) for r in conn.execute("PRAGMA table_info(researchers)")]
    experiment_cols = [(r[1], r[2], r[5]) for r in conn.execute("PRAGMA table_info(experiments)")]
    assert researcher_cols == [("id", "INTEGER", 1), ("name", "TEXT", 0)]
    assert experiment_cols == [
        ("id", "INTEGER", 1), ("doc_data", "TEXT", 0), ("researcher_id", "INTEGER", 0)
    ]

    indexes = list(conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='experiments'"
    ))
    assert len(indexes) > 0, "No index found on 'experiments' table to optimize the query"
    indexed_columns = []
    for (name,) in indexes:
        indexed_columns.append([row[2] for row in conn.execute(f"PRAGMA index_info({json.dumps(name)})")])
    assert any(cols and cols[0] == "researcher_id" for cols in indexed_columns), \
        f"No experiments index begins with researcher_id: {indexed_columns!r}"


def test_script_end_to_end():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, "Submitted script is empty"
    with open(SCRIPT_PATH, "rb") as f:
        compile(f.read(), SCRIPT_PATH, "exec")

    token = uuid.uuid4().hex
    dynamic_researchers = [(731, "O'Reilly-" + token), (947, "Researcher-" + token)]
    dynamic_docs = [
        {"id": 5101, "researcher_id": 731, "data": "Dynamic A " + token},
        {"id": 5102, "researcher_id": 947, "data": "Dynamic B " + token},
    ]

    try:
        with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "name"])
            writer.writerows(dynamic_researchers)
        with open(JSONL_PATH, "w", encoding="utf-8") as f:
            for doc in dynamic_docs:
                f.write(json.dumps(doc) + "\n")

        dynamic_events = run_script()
        assert os.path.isfile(DB_PATH), f"Database missing: {DB_PATH}"
        conn = sqlite3.connect(DB_PATH)
        try:
            check_schema_and_index(conn)
            assert list(conn.execute("SELECT id, name FROM researchers ORDER BY id")) == dynamic_researchers
            rows = list(conn.execute(
                "SELECT id, doc_data, researcher_id FROM experiments ORDER BY id"
            ))
            assert [(r[0], r[2]) for r in rows] == [(5101, 731), (5102, 947)]
            assert [json.loads(r[1]) for r in rows] == dynamic_docs
            read_and_check_log(conn)
        finally:
            conn.close()
        check_concurrency(dynamic_events)

        with open(CSV_PATH, "wb") as f:
            f.write(ORIGINAL_CSV)
        with open(JSONL_PATH, "wb") as f:
            f.write(ORIGINAL_JSONL)

        final_events = run_script()
        assert os.path.isfile(DB_PATH), f"Database missing: {DB_PATH}"
        conn = sqlite3.connect(DB_PATH)
        try:
            check_schema_and_index(conn)
            researchers = list(conn.execute("SELECT id, name FROM researchers ORDER BY id"))
            assert researchers == [(1, "Alice"), (2, "Bob")], \
                "Data in 'researchers' table is incorrect"
            experiments = list(conn.execute(
                "SELECT id, researcher_id FROM experiments ORDER BY id"
            ))
            assert experiments == [(101, 1), (102, 2)], \
                "Data in 'experiments' table is incorrect"
            read_and_check_log(conn)
        finally:
            conn.close()
        check_concurrency(final_events)

        parameterized_inserts = [
            e for e in final_events
            if e.get("kind") == "sql"
            and re.search(r"^\s*INSERT\b", e.get("sql", ""), re.I)
            and e.get("has_parameters")
            and "?" in e.get("sql", "")
        ]
        assert parameterized_inserts, \
            "No parameterized INSERT using placeholders was observed"
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(ORIGINAL_CSV)
        with open(JSONL_PATH, "wb") as f:
            f.write(ORIGINAL_JSONL)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
