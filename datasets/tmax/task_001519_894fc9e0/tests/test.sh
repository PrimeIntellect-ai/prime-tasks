#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import os
import re
import secrets
import subprocess
from decimal import Decimal

import pytest

EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
SCRIPT_PATH = "/home/user/detector.py"


def run_detector(csv_path, env=None):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, csv_path],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    return result.stdout.strip(), result.stderr.strip()


def test_detector_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]

    bypassed_evil = []
    modified_clean = []

    for evil_file in evil_files:
        stdout, _ = run_detector(evil_file)
        if stdout != "SUSPICIOUS":
            bypassed_evil.append((os.path.basename(evil_file), stdout))

    for clean_file in clean_files:
        stdout, _ = run_detector(clean_file)
        if stdout != "OK":
            modified_clean.append((os.path.basename(clean_file), stdout))

    error_messages = []
    if bypassed_evil:
        files_str = ", ".join(f"{f} (output: {out})" for f, out in bypassed_evil)
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {files_str}")

    if modified_clean:
        files_str = ", ".join(f"{f} (output: {out})" for f, out in modified_clean)
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {files_str}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle(rows):
    edges = {}
    accounts = set()
    for row in rows:
        source = row[1]
        target = row[2]
        accounts.update((source, target))
        edges.setdefault((source, target), []).append(row)

    for a, b, c in itertools.permutations(accounts, 3):
        if (a, b) not in edges or (b, c) not in edges or (c, a) not in edges:
            continue
        for first, second, third in itertools.product(
            edges[(a, b)], edges[(b, c)], edges[(c, a)]
        ):
            times = [int(first[4]), int(second[4]), int(third[4])]
            total = Decimal(str(first[3])) + Decimal(str(second[3])) + Decimal(str(third[3]))
            if max(times) - min(times) <= 60 and total > Decimal("5000"):
                return "SUSPICIOUS"
    return "OK"


def write_csv(path, rows):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "event_id", "source_node", "target_node", "transfer_value", "epoch_time"
        ])
        writer.writerows(rows)


def unique_accounts(count):
    token = secrets.token_hex(6)
    return [f"acct_{token}_{i}" for i in range(count)]


def generated_cases():
    cases = []
    event = 1

    # Randomized positive cases, with unrelated transactions and shuffled row order.
    for _ in range(8):
        a, b, c, d, e, f = unique_accounts(6)
        base = secrets.randbelow(100000) + 1000
        offsets = sorted([secrets.randbelow(61) for _ in range(3)])
        amounts = [1800 + secrets.randbelow(2201) for _ in range(3)]
        rows = [
            [str(event), a, b, str(amounts[0]), str(base + offsets[0])],
            [str(event + 1), b, c, str(amounts[1]), str(base + offsets[1])],
            [str(event + 2), c, a, str(amounts[2]), str(base + offsets[2])],
            [str(event + 3), d, e, "9000", str(base - 500)],
            [str(event + 4), e, f, "9000", str(base + 500)],
        ]
        event += 5
        secrets.SystemRandom().shuffle(rows)
        assert oracle(rows) == "SUSPICIOUS"
        cases.append(rows)

    # Boundary and wrong-shape negative cases.
    for _ in range(2):
        a, b, c, d = unique_accounts(4)
        base = secrets.randbelow(100000) + 1000
        templates = [
            # Total is exactly 5000, not greater than 5000.
            [[a, b, "2000", 0], [b, c, "1500", 20], [c, a, "1500", 60]],
            # High-value triangle spans 61 seconds.
            [[a, b, "6000", 0], [b, c, "6000", 30], [c, a, "6000", 61]],
            # Two-account loop only.
            [[a, b, "7000", 0], [b, a, "7000", 10]],
            # Four-account loop only.
            [[a, b, "3000", 0], [b, c, "3000", 10], [c, d, "3000", 20], [d, a, "3000", 30]],
            # Acyclic high-value transfers.
            [[a, b, "9000", 0], [b, c, "9000", 10], [c, d, "9000", 20]],
        ]
        for template in templates:
            rows = []
            for source, target, amount, offset in template:
                rows.append([str(event), source, target, amount, str(base + offset)])
                event += 1
            secrets.SystemRandom().shuffle(rows)
            assert oracle(rows) == "OK"
            cases.append(rows)

    secrets.SystemRandom().shuffle(cases)
    return cases


def test_runtime_generated_corpus(tmp_path):
    observed = set()
    for rows in generated_cases():
        expected = oracle(rows)
        observed.add(expected)
        path = tmp_path / f"{secrets.token_hex(12)}.csv"
        write_csv(path, rows)
        stdout, _ = run_detector(str(path))
        assert stdout == expected, f"Expected {expected}, got {stdout!r} for generated input"
    assert observed == {"SUSPICIOUS", "OK"}


def test_uses_sqlite_and_sql_graph_analysis(tmp_path):
    # Install a verification-only sitecustomize hook that transparently records
    # sqlite3 calls made by the submitted process.
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    log_path = tmp_path / "sqlite_trace.jsonl"
    hook = r'''
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_log_path = os.environ.get("SQLTRACE_LOG")

def _log(record):
    if _log_path:
        with open(_log_path, "a") as handle:
            handle.write(json.dumps(record) + "\\n")

class TracedCursor:
    def __init__(self, cursor):
        self._cursor = cursor
    def execute(self, sql, *args, **kwargs):
        _log({"op": "execute", "sql": str(sql), "parameterized": bool(args or kwargs)})
        self._cursor.execute(sql, *args, **kwargs)
        return self
    def executemany(self, sql, *args, **kwargs):
        _log({"op": "executemany", "sql": str(sql), "parameterized": True})
        self._cursor.executemany(sql, *args, **kwargs)
        return self
    def executescript(self, sql, *args, **kwargs):
        _log({"op": "executescript", "sql": str(sql), "parameterized": False})
        self._cursor.executescript(sql, *args, **kwargs)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class TracedConnection:
    def __init__(self, connection):
        self._connection = connection
    def cursor(self, *args, **kwargs):
        return TracedCursor(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.execute(sql, *args, **kwargs)
    def executemany(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.executemany(sql, *args, **kwargs)
    def executescript(self, sql, *args, **kwargs):
        cursor = self.cursor()
        return cursor.executescript(sql, *args, **kwargs)
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)

def traced_connect(*args, **kwargs):
    _log({"op": "connect", "database": str(args[0] if args else kwargs.get("database", ""))})
    return TracedConnection(_original_connect(*args, **kwargs))

sqlite3.connect = traced_connect
'''
    (hook_dir / "sitecustomize.py").write_text(hook)

    a, b, c = unique_accounts(3)
    rows = [
        [secrets.token_hex(4), a, b, "2000.25", "1000"],
        [secrets.token_hex(4), b, c, "2000.25", "1020"],
        [secrets.token_hex(4), c, a, "2000.25", "1040"],
    ]
    csv_path = tmp_path / f"{secrets.token_hex(12)}.csv"
    write_csv(csv_path, rows)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["SQLTRACE_LOG"] = str(log_path)
    stdout, _ = run_detector(str(csv_path), env=env)
    assert stdout == "SUSPICIOUS"
    assert log_path.is_file(), "The detector did not open a SQLite database"

    records = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
    assert any(r.get("op") == "connect" for r in records), "No sqlite3 connection was made"
    statements = [r for r in records if r.get("sql")]
    normalized = [re.sub(r"\\s+", " ", r["sql"].upper()) for r in statements]
    assert any("CREATE TABLE" in sql and "TRANSFER_EVENTS" in sql for sql in normalized), \
        "The reverse-engineered transfer_events table was not created"
    assert any("INSERT" in sql and "TRANSFER_EVENTS" in sql for sql in normalized), \
        "CSV rows were not loaded into SQLite"
    assert any(r.get("parameterized") and "INSERT" in r.get("sql", "").upper() for r in statements), \
        "CSV loading did not use a parameterized SQL statement"

    graph_queries = []
    for sql in normalized:
        if "SELECT" not in sql:
            continue
        if ("WITH RECURSIVE" in sql or re.search(r"\\bOVER\\s*\\(", sql)
                or sql.count(" JOIN ") >= 2 or sql.count("TRANSFER_EVENTS") >= 3):
            graph_queries.append(sql)
    assert graph_queries, "No SQL window, recursive CTE, or self-join graph analysis was executed"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
