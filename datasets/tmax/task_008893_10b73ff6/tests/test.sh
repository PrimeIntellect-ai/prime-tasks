#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp -a /home/user/transactions.ttl "$backup_dir/transactions.ttl"
cp -a /home/user/audit_logs.db "$backup_dir/audit_logs.db"
if [ -e /home/user/audit_report.csv ]; then
    cp -a /home/user/audit_report.csv "$backup_dir/audit_report.csv"
    had_report=1
else
    had_report=0
fi

restore_files() {
    cp -a "$backup_dir/transactions.ttl" /home/user/transactions.ttl
    cp -a "$backup_dir/audit_logs.db" /home/user/audit_logs.db
    if [ "$had_report" = 1 ]; then
        cp -a "$backup_dir/audit_report.csv" /home/user/audit_report.csv
    else
        rm -f /home/user/audit_report.csv
    fi
    rm -rf "$backup_dir"
}
trap restore_files EXIT

hook_dir=$(mktemp -d)
chmod 755 "$hook_dir"
cat << 'HOOK_EOF' > "$hook_dir/sitecustomize.py"
import os

TRACE = os.environ.get("AUDIT_TRACE")

def log(kind, value):
    if TRACE:
        text = str(value).replace("\n", " ").replace("\r", " ")
        with open(TRACE, "a", encoding="utf-8") as f:
            f.write(kind + "\t" + text + "\n")

try:
    import rdflib
    _parse = rdflib.Graph.parse
    _query = rdflib.Graph.query

    def traced_parse(self, *args, **kwargs):
        source = args[0] if args else kwargs.get("source", kwargs.get("location", ""))
        log("RDF_PARSE", source)
        return _parse(self, *args, **kwargs)

    def traced_query(self, query_object, *args, **kwargs):
        log("SPARQL", query_object)
        return _query(self, query_object, *args, **kwargs)

    rdflib.Graph.parse = traced_parse
    rdflib.Graph.query = traced_query
except Exception:
    pass

try:
    import sqlite3
    _connect = sqlite3.connect

    class TracedCursor(sqlite3.Cursor):
        def execute(self, sql, *args, **kwargs):
            log("SQL", sql)
            return super().execute(sql, *args, **kwargs)

        def executemany(self, sql, *args, **kwargs):
            log("SQL", sql)
            return super().executemany(sql, *args, **kwargs)

    class TracedConnection(sqlite3.Connection):
        def cursor(self, *args, **kwargs):
            kwargs.setdefault("factory", TracedCursor)
            return super().cursor(*args, **kwargs)

        def execute(self, sql, *args, **kwargs):
            log("SQL", sql)
            return super().execute(sql, *args, **kwargs)

        def executemany(self, sql, *args, **kwargs):
            log("SQL", sql)
            return super().executemany(sql, *args, **kwargs)

    def traced_connect(*args, **kwargs):
        if len(args) < 6 and "factory" not in kwargs:
            kwargs["factory"] = TracedConnection
        return _connect(*args, **kwargs)

    sqlite3.connect = traced_connect
except Exception:
    pass
HOOK_EOF
chmod 644 "$hook_dir/sitecustomize.py"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import subprocess
import uuid
from pathlib import Path

HOME = Path("/home/user")
SCRIPT = HOME / "run_audit.py"
REPORT = HOME / "audit_report.csv"
TTL = HOME / "transactions.ttl"
DB = HOME / "audit_logs.db"
HOOK_DIR = os.environ["AUDIT_HOOK_DIR"]


def read_rows():
    assert REPORT.exists(), f"Expected output file {REPORT} does not exist."
    assert REPORT.is_file(), f"{REPORT} is not a regular file."
    with REPORT.open("r", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert len(rows) >= 1, f"{REPORT} is empty."
    return [[cell.strip() for cell in row] for row in rows]


def write_fixture(ids, latest_users):
    a, b, c = ids
    decoy = "D" + uuid.uuid4().hex[:10]
    e = "E" + uuid.uuid4().hex[:10]
    f = "F" + uuid.uuid4().hex[:10]
    x = "X" + uuid.uuid4().hex[:10]
    y = "Y" + uuid.uuid4().hex[:10]

    TTL.write_text(f'''@prefix ex: <http://example.org/> .
@prefix tx: <http://example.org/tx/> .

tx:{b} ex:amount 27001 ; ex:transfersTo tx:{c} .
tx:{c} ex:amount 18002 ; ex:transfersTo tx:{a} .
tx:{a} ex:amount 12003 ; ex:transfersTo tx:{b} .

# This is a cycle, but one amount is exactly the excluded threshold.
tx:{decoy} ex:amount 10000 ; ex:transfersTo tx:{e} .
tx:{e} ex:amount 99999 ; ex:transfersTo tx:{f} .
tx:{f} ex:amount 99999 ; ex:transfersTo tx:{decoy} .

# High-value edges that do not form a three-cycle.
tx:{x} ex:amount 88000 ; ex:transfersTo tx:{y} .
tx:{y} ex:amount 99000 ; ex:transfersTo tx:{a} .
''', encoding="utf-8")

    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    try:
        con.executescript('''
            CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, department TEXT);
            CREATE TABLE approvals (id INTEGER PRIMARY KEY, tx_id TEXT, user_id INTEGER, approved_at DATETIME);
        ''')
        old_users = ["old_" + uuid.uuid4().hex[:12] for _ in ids]
        all_users = old_users + latest_users
        for i, username in enumerate(all_users, 1):
            con.execute("INSERT INTO users VALUES (?, ?, ?)", (i, username, "Audit"))
        approval_id = 1
        for index, tx_id in enumerate(ids):
            con.execute(
                "INSERT INTO approvals VALUES (?, ?, ?, ?)",
                (approval_id, tx_id, index + 1, "2024-01-01 08:00:00"),
            )
            approval_id += 1
            con.execute(
                "INSERT INTO approvals VALUES (?, ?, ?, ?)",
                (approval_id, tx_id, len(ids) + index + 1, f"2025-02-0{index + 2} 17:30:00"),
            )
            approval_id += 1
        # Unrelated approval must not enter the report.
        con.execute(
            "INSERT INTO approvals VALUES (?, ?, ?, ?)",
            (approval_id, x, 1, "2030-12-31 23:59:59"),
        )
        con.commit()
    finally:
        con.close()
    os.chmod(TTL, 0o644)
    os.chmod(DB, 0o666)


def run_and_trace(expected_row):
    trace = Path("/tmp/audit_trace_" + uuid.uuid4().hex)
    trace.touch()
    os.chmod(trace, 0o666)
    if REPORT.exists():
        REPORT.unlink()

    env = os.environ.copy()
    env["PYTHONPATH"] = HOOK_DIR
    env["AUDIT_TRACE"] = str(trace)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env",
         f"PYTHONPATH={HOOK_DIR}", f"AUDIT_TRACE={trace}",
         "python3", str(SCRIPT)],
        cwd=str(HOME), env=env, text=True, capture_output=True, timeout=30,
    )
    assert result.returncode == 0, (
        f"run_audit.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    rows = read_rows()
    assert expected_row in rows, f"Could not find dynamically expected row {expected_row}. Found: {rows}"

    lines = trace.read_text(encoding="utf-8").splitlines()
    parse_calls = [line for line in lines if line.startswith("RDF_PARSE\t")]
    sparql_calls = [line.split("\t", 1)[1] for line in lines if line.startswith("SPARQL\t")]
    sql_calls = [line.split("\t", 1)[1] for line in lines if line.startswith("SQL\t")]

    assert parse_calls, "The executed script did not call rdflib.Graph.parse to load RDF."
    assert any("transactions.ttl" in call for call in parse_calls), (
        "The executed script did not parse transactions.ttl."
    )
    assert sparql_calls, "The executed script did not call rdflib.Graph.query."
    assert any(
        "transfersto" in query.lower()
        and "amount" in query.lower()
        and "10000" in query
        for query in sparql_calls
    ), "No executed SPARQL query checked transfersTo, amount, and the 10000 threshold."

    window_queries = []
    for sql in sql_calls:
        normalized = re.sub(r"\s+", " ", sql.lower())
        if (re.search(r"row_number\s*\(\s*\)\s*over\s*\(", normalized)
                and "partition by" in normalized
                and "order by" in normalized
                and "approvals" in normalized
                and "users" in normalized):
            window_queries.append(sql)
    assert window_queries, (
        "The executed pipeline did not use a single SQL query containing "
        "ROW_NUMBER() OVER (...), partitioning/ordering, approvals, and users."
    )
    trace.unlink(missing_ok=True)


def test_complete_audit_pipeline():
    # Preserve the original verifier's assertions against the initially supplied data.
    original_rows = read_rows()
    expected_original = [
        "A001", "B002", "C003",
        "alice_compliance", "bob_finance", "charlie_admin",
    ]
    assert expected_original in original_rows, (
        f"Could not find the expected row {expected_original} in {REPORT}. Found: {original_rows}"
    )
    assert SCRIPT.exists(), f"Expected script {SCRIPT} does not exist."
    assert SCRIPT.is_file(), f"{SCRIPT} is not a regular file."

    # Exercise the artifact on fresh, unpredictable RDF and SQLite contents twice.
    for _ in range(2):
        ids = sorted(["T" + uuid.uuid4().hex[:12] for _ in range(3)])
        users = ["approver_" + uuid.uuid4().hex[:14] for _ in range(3)]
        write_fixture(ids, users)
        run_and_trace(ids + users)
TEST_EOF

if AUDIT_HOOK_DIR="$hook_dir" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
rm -rf "$hook_dir"
