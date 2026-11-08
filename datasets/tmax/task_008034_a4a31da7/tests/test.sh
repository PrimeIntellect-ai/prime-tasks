#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import textwrap
import uuid
import pytest

SCRIPT_PATH = "/home/user/db_report.py"
REPORT_PATH = "/home/user/report.json"
DB_PATH = "/home/user/backups.db"
JSONL_PATH = "/home/user/nosql_metrics.jsonl"
TRACE_DIR = "/tmp/db_report_instrument"
TRACE_PATH = "/tmp/db_report_sql_trace.jsonl"


def expected_report(datacenter):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
        SELECT s.hostname, COUNT(b.job_id)
        FROM servers s
        JOIN backup_jobs b ON s.id = b.server_id
        WHERE s.datacenter = ? AND b.status = 'FAILED'
        GROUP BY s.hostname
    """
    cursor.execute(query, (datacenter,))
    failed_servers = {row[0]: row[1] for row in cursor.fetchall()}
    conn.close()

    expected = {
        hostname: {"failures": failures, "total_bytes": 0}
        for hostname, failures in failed_servers.items()
    }
    with open(JSONL_PATH, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            hostname = record.get("hostname")
            if hostname in expected and record.get("type") == "backup":
                expected[hostname]["total_bytes"] += record.get("bytes_transferred", 0)
    return expected


def read_report():
    assert os.path.isfile(REPORT_PATH), f"Report not generated at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report at {REPORT_PATH} is not valid JSON")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_script_uses_parameterized_queries():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "?" in content, "Script does not appear to use SQLite parameterization ('?') for the query."


def test_run_script_and_verify_report():
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "us-east-1"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    actual_report = read_report()
    expected = expected_report("us-east-1")
    assert actual_report == expected, f"Report content mismatch. Expected {expected}, got {actual_report}"


def install_sql_trace():
    os.makedirs(TRACE_DIR, exist_ok=True)
    sitecustomize = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("DB_REPORT_SQL_TRACE")


def _safe(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)


def _log(sql, parameters):
    if not _trace_path:
        return
    if isinstance(parameters, dict):
        values = [_safe(v) for v in parameters.values()]
    elif isinstance(parameters, (list, tuple)):
        values = [_safe(v) for v in parameters]
    else:
        values = [_safe(parameters)]
    with open(_trace_path, "a") as f:
        f.write(json.dumps({"sql": str(sql), "parameters": values}) + "\n")


class CursorProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def execute(self, sql, parameters=()):
        result = self._inner.execute(sql, parameters)
        _log(sql, parameters)
        return self

    def executemany(self, sql, seq):
        return self._inner.executemany(sql, seq)

    def executescript(self, sql):
        return self._inner.executescript(sql)

    def __iter__(self):
        return iter(self._inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        setattr(self._inner, name, value)


class ConnectionProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        return self.cursor().execute(sql, parameters)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        setattr(self._inner, name, value)


def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''
    with open(os.path.join(TRACE_DIR, "sitecustomize.py"), "w") as f:
        f.write(textwrap.dedent(sitecustomize))


def create_random_fixture():
    token = uuid.uuid4().hex
    dc_a = "dc-a-" + token
    dc_b = "dc-b-" + token
    dc_other = "dc-other-" + token
    hosts = ["alpha-" + token, "beta-" + token, "gamma-" + token,
             "nofail-" + token, "outside-" + token]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, datacenter TEXT);
        CREATE TABLE backup_jobs (job_id INTEGER PRIMARY KEY, server_id INTEGER, status TEXT, timestamp DATETIME);
    """)
    conn.executemany("INSERT INTO servers VALUES (?, ?, ?)", [
        (1, hosts[0], dc_a), (2, hosts[1], dc_a), (3, hosts[2], dc_b),
        (4, hosts[3], dc_a), (5, hosts[4], dc_other)
    ])
    jobs = []
    job_id = 1000
    for server_id, failures, successes in [(1, 3, 1), (2, 1, 2), (3, 2, 0), (4, 0, 2), (5, 4, 0)]:
        for _ in range(failures):
            jobs.append((job_id, server_id, "FAILED", "2026-01-01 00:00:00"))
            job_id += 1
        for _ in range(successes):
            jobs.append((job_id, server_id, "SUCCESS", "2026-01-02 00:00:00"))
            job_id += 1
    conn.executemany("INSERT INTO backup_jobs VALUES (?, ?, ?, ?)", jobs)
    conn.commit()
    conn.close()

    records = [
        {"hostname": hosts[0], "type": "backup", "bytes_transferred": 111, "duration_seconds": 1},
        {"hostname": hosts[0], "type": "backup", "bytes_transferred": 222, "duration_seconds": 2},
        {"hostname": hosts[0], "type": "restore", "bytes_transferred": 9999, "duration_seconds": 3},
        {"hostname": hosts[1], "type": "backup", "bytes_transferred": 444, "duration_seconds": 4},
        {"hostname": hosts[2], "type": "restore", "bytes_transferred": 8888, "duration_seconds": 5},
        {"hostname": hosts[3], "type": "backup", "bytes_transferred": 777, "duration_seconds": 6},
        {"hostname": hosts[4], "type": "backup", "bytes_transferred": 555, "duration_seconds": 7},
        {"hostname": "unrelated-" + token, "type": "backup", "bytes_transferred": 12345, "duration_seconds": 8}
    ]
    with open(JSONL_PATH, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    return [dc_a, dc_b]


def assert_compliant_query_was_executed(datacenter):
    assert os.path.isfile(TRACE_PATH), "No SQLite statements were executed"
    with open(TRACE_PATH, "r") as f:
        traces = [json.loads(line) for line in f if line.strip()]

    for trace in traces:
        sql = trace.get("sql", "")
        params = trace.get("parameters", [])
        normalized = re.sub(r"\s+", " ", sql).strip()
        has_dc_placeholder = (
            re.search(r"\bdatacenter\b\s*=\s*\?", normalized, re.I) or
            re.search(r"\?\s*=\s*[^ ]*\bdatacenter\b", normalized, re.I)
        )
        if (re.search(r"\bWITH\b", normalized, re.I)
                and re.search(r"\bJOIN\b", normalized, re.I)
                and "?" in normalized
                and has_dc_placeholder
                and datacenter in params
                and datacenter not in normalized):
            return
    pytest.fail("No executed SQL query used a CTE, JOIN, and a bound '?' datacenter parameter")


def test_randomized_datacenters_and_executed_sql_structure():
    datacenters = create_random_fixture()
    install_sql_trace()
    for datacenter in datacenters:
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        if os.path.exists(TRACE_PATH):
            os.remove(TRACE_PATH)
        env = os.environ.copy()
        env["PYTHONPATH"] = TRACE_DIR + os.pathsep + env.get("PYTHONPATH", "")
        env["DB_REPORT_SQL_TRACE"] = TRACE_PATH
        result = subprocess.run(
            ["python3", SCRIPT_PATH, datacenter],
            capture_output=True,
            text=True,
            env=env
        )
        assert result.returncode == 0, f"Script failed for randomized datacenter. stderr: {result.stderr}"
        expected = expected_report(datacenter)
        actual = read_report()
        assert actual == expected, f"Report content mismatch. Expected {expected}, got {actual}"
        assert_compliant_query_was_executed(datacenter)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
