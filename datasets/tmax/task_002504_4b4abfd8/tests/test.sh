#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import csv
import json
import os
import runpy
import secrets
import sqlite3

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "generate_report.py")
REPORT = os.path.join(HOME, "regional_sales_report.json")
PLAN = os.path.join(HOME, "query_plan.txt")
CSV_PATHS = [os.path.join(HOME, n) for n in ("customers.csv", "products.csv", "sales.csv")]


def normalize_sql(sql):
    return " ".join(str(sql).upper().split())


class InstrumentedCursor:
    def __init__(self, cursor, owner):
        self._cursor = cursor
        self._owner = owner

    def execute(self, sql, parameters=()):
        normalized = normalize_sql(sql)

        # Capture the indexes that really exist immediately before the report SELECT.
        if (not normalized.startswith("EXPLAIN") and "SELECT" in normalized
                and "SUM" in normalized and "SALES" in normalized
                and "CUSTOMERS" in normalized and "PRODUCTS" in normalized):
            indexes = {}
            for row in self._owner._conn.execute("PRAGMA index_list('sales')").fetchall():
                name = row[1]
                cols = [r[2] for r in self._owner._conn.execute(
                    "PRAGMA index_info(%s)" % json.dumps(name)
                ).fetchall()]
                indexes[name] = cols
            self._owner.index_snapshots.append(indexes)

        result = self._cursor.execute(sql, parameters)

        # Independently execute the exact EXPLAIN statement and retain SQLite's rows.
        if normalized.startswith("EXPLAIN QUERY PLAN"):
            rows = self._owner._conn.cursor().execute(sql, parameters).fetchall()
            self._owner.explains.append((str(sql), rows))
        return self

    def executemany(self, sql, seq):
        self._cursor.executemany(sql, seq)
        return self

    def executescript(self, sql):
        self._cursor.executescript(sql)
        return self

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchmany(self, *args):
        return self._cursor.fetchmany(*args)

    def fetchall(self):
        return self._cursor.fetchall()

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class InstrumentedConnection:
    def __init__(self, conn):
        self._conn = conn
        self.index_snapshots = []
        self.explains = []

    def cursor(self, *args, **kwargs):
        return InstrumentedCursor(self._conn.cursor(*args, **kwargs), self)

    def execute(self, sql, parameters=()):
        cur = self.cursor()
        return cur.execute(sql, parameters)

    def executemany(self, sql, seq):
        cur = self.cursor()
        return cur.executemany(sql, seq)

    def executescript(self, sql):
        cur = self.cursor()
        return cur.executescript(sql)

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, *args):
        return self._conn.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._conn, name)


def parse_plan_file(path):
    text = open(path, "r", encoding="utf-8").read().strip()
    assert text, "query_plan.txt is empty"

    candidates = [text]
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if lines:
        candidates.append("[" + ",".join(lines) + "]")

    for candidate in candidates:
        for parser in (ast.literal_eval, json.loads):
            try:
                value = parser(candidate)
            except Exception:
                continue
            if isinstance(value, tuple) and len(value) == 4:
                value = [value]
            if isinstance(value, list) and all(
                    isinstance(row, (list, tuple)) and len(row) == 4 for row in value):
                return [tuple(row) for row in value]
    raise AssertionError("query_plan.txt is not raw EXPLAIN QUERY PLAN row output")


def read_and_check_report(expected):
    assert os.path.isfile(REPORT), "File not found: " + REPORT
    with open(REPORT, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, list), "The report must be a JSON array"
    assert all(isinstance(x, dict) and set(x) == {"region", "category", "total_sales"}
               for x in data), "Each report item must have exactly the required fields"
    key = lambda x: (x["region"], x["category"])
    assert sorted(data, key=key) == sorted(expected, key=key), \
        "JSON data does not match the expected aggregated results"


def check_execution(expected):
    for path in (REPORT, PLAN):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    real_connect = sqlite3.connect
    connections = []

    def wrapped_connect(*args, **kwargs):
        conn = InstrumentedConnection(real_connect(*args, **kwargs))
        connections.append(conn)
        return conn

    sqlite3.connect = wrapped_connect
    old_cwd = os.getcwd()
    try:
        os.chdir(HOME)
        runpy.run_path(SCRIPT, run_name="__main__")
    finally:
        os.chdir(old_cwd)
        sqlite3.connect = real_connect

    read_and_check_report(expected)
    assert os.path.isfile(PLAN), "File not found: " + PLAN
    plan_text = open(PLAN, "r", encoding="utf-8").read().upper()
    assert any(word in plan_text for word in
               ["SCAN", "SEARCH", "COVERING INDEX", "USE TEMP B-TREE", "LIST SUBQUERY"]), \
        "query_plan.txt does not appear to contain valid EXPLAIN QUERY PLAN output"

    snapshots = [s for conn in connections for s in conn.index_snapshots]
    assert snapshots, "The aggregation SELECT was not observed executing"
    valid_snapshot = False
    for snapshot in snapshots:
        first_columns = [cols[0].lower() for cols in snapshot.values() if cols]
        if "customer_id" in first_columns and "product_id" in first_columns:
            valid_snapshot = True
            break
    assert valid_snapshot, \
        "Distinct usable sales indexes on customer_id and product_id must exist before the SELECT"

    explains = [item for conn in connections for item in conn.explains]
    assert explains, "The script did not execute EXPLAIN QUERY PLAN"
    parsed_plan = parse_plan_file(PLAN)
    matching = []
    for sql, rows in explains:
        normalized = normalize_sql(sql)
        if ("SUM" in normalized and "SALES" in normalized and
                "CUSTOMERS" in normalized and "PRODUCTS" in normalized):
            matching.append([tuple(row) for row in rows])
    assert matching, "EXPLAIN QUERY PLAN was not run for the aggregation query"
    assert parsed_plan in matching, \
        "query_plan.txt does not contain the raw rows produced by the executed EXPLAIN"


def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


def main():
    assert os.path.isfile(SCRIPT), "File not found: " + SCRIPT
    source = open(SCRIPT, "r", encoding="utf-8").read().upper()
    assert "CREATE INDEX" in source, "generate_report.py is missing CREATE INDEX statement(s)"
    assert "SALES" in source, "generate_report.py does not reference sales in index creation"
    compile(open(SCRIPT, "rb").read(), SCRIPT, "exec")

    original = {path: open(path, "rb").read() for path in CSV_PATHS}
    nonce = secrets.token_hex(6)
    north = "Region_A_" + nonce
    south = "Region_B_" + nonce
    west = "Region_C_" + nonce
    cat_a = "Category_X_" + nonce
    cat_b = "Category_Y_" + nonce

    try:
        write_csv(CSV_PATHS[0], [
            ["customer_id", "region"], [11, north], [12, south],
            [13, north], [14, west], [15, "Unused_" + nonce]
        ])
        write_csv(CSV_PATHS[1], [
            ["product_id", "category"], [201, cat_a], [202, cat_b],
            [203, cat_a], [204, "UnusedCat_" + nonce]
        ])
        write_csv(CSV_PATHS[2], [
            ["transaction_id", "customer_id", "product_id", "amount"],
            [1, 11, 201, 12.5], [2, 13, 203, 7.5], [3, 11, 202, 3.0],
            [4, 12, 201, 4.25], [5, 14, 202, 9.75], [6, 11, 201, 2.0]
        ])
        challenge_expected = [
            {"region": north, "category": cat_a, "total_sales": 22.0},
            {"region": north, "category": cat_b, "total_sales": 3.0},
            {"region": south, "category": cat_a, "total_sales": 4.25},
            {"region": west, "category": cat_b, "total_sales": 9.75},
        ]
        check_execution(challenge_expected)
    finally:
        for path, content in original.items():
            with open(path, "wb") as f:
                f.write(content)

    # Re-run on the shipped data so the required final artifacts remain correct.
    original_expected = [
        {"region": "East", "category": "Electronics", "total_sales": 600.0},
        {"region": "North", "category": "Electronics", "total_sales": 500.0},
        {"region": "North", "category": "Home", "total_sales": 100.0},
        {"region": "South", "category": "Clothing", "total_sales": 50.0},
        {"region": "South", "category": "Electronics", "total_sales": 150.0},
        {"region": "West", "category": "Clothing", "total_sales": 45.0},
    ]
    check_execution(original_expected)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
