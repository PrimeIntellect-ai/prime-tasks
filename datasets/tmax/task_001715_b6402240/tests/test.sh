#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess

DB_PATH = "/home/user/source.db"
SCRIPT_PATH = "/home/user/etl.sh"
SQL_PATH = "/home/user/optimize.sql"


def test_optimize_sql_exists_and_contains_indexes():
    assert os.path.isfile(SQL_PATH), f"File {SQL_PATH} does not exist."

    with open(SQL_PATH, "r") as f:
        content = f.read().upper()

    # Preserve the original assertion and additionally require three actual
    # CREATE INDEX statements rather than an occurrence in a comment.
    assert "CREATE INDEX" in content, f"{SQL_PATH} does not contain CREATE INDEX statements."
    without_comments = re.sub(r"/\*.*?\*/|--[^\n]*", "", content, flags=re.S)
    statements = re.findall(r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\b", without_comments)
    assert len(statements) >= 3, f"Expected at least 3 CREATE INDEX statements in {SQL_PATH}."


def _custom_indexes(conn, table):
    result = []
    for row in conn.execute(f"PRAGMA index_list('{table}')"):
        name = row[1]
        if name.startswith("sqlite_autoindex"):
            continue
        columns = [r[2] for r in conn.execute(f"PRAGMA index_info('{name}')")]
        result.append((name, columns))
    return result


def test_indexes_applied_to_db():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';"
    ).fetchall()

    # Preserve the original count assertion.
    assert len(indexes) >= 3, f"Expected at least 3 custom indexes in {DB_PATH}, found {len(indexes)}."

    # The indexes must cover the actual filter and join columns, not unrelated columns.
    required = [
        ("orders", "order_date"),
        ("orders", "customer_id"),
        ("order_items", "order_id"),
    ]
    for table, column in required:
        table_indexes = _custom_indexes(conn, table)
        assert any(column in columns for _, columns in table_indexes), (
            f"No applied custom index on required column {table}.{column}; "
            f"found {table_indexes}."
        )
    conn.close()


def test_etl_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    # Preserve the original assertion.
    assert "?" in content, f"Script {SCRIPT_PATH} does not seem to use parameterized queries (missing '?')."

    # A question mark in a shell/SQL comment is not a parameterized query.
    uncommented = re.sub(r"/\*.*?\*/|--[^\n]*|^[ \t]*#[^\n]*", "", content, flags=re.S | re.M)
    select_match = re.search(r"\bSELECT\b.*?\bWHERE\b.*?(\?(?:\d+)?)", uncommented, flags=re.I | re.S)
    assert select_match, "The ETL SELECT/WHERE query does not contain a positional SQLite parameter."
    placeholder = re.escape(select_match.group(1))
    assert re.search(rf"\.parameter\s+set\s+{placeholder}(?:\s|$)", uncommented, flags=re.I), (
        "The query parameter is not bound with the sqlite3 CLI .parameter command."
    )


def _run_and_read_lines(date_arg):
    report_path = f"/home/user/report_{date_arg}.csv"
    if os.path.exists(report_path):
        os.remove(report_path)
    result = subprocess.run([SCRIPT_PATH, date_arg], capture_output=True, text=True)
    assert result.returncode == 0, f"Execution of {SCRIPT_PATH} failed: {result.stderr}"
    assert os.path.isfile(report_path), f"Report file {report_path} was not created."
    with open(report_path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_etl_script_execution_2023_10_15():
    lines = _run_and_read_lines("2023-10-15")
    expected_lines = [
        "customer_id,customer_name,total_spent",
        "1,Alice Smith,40.00",
        "2,Bob Jones,21.00",
    ]
    assert lines == expected_lines, "Report contents do not match expected output for 2023-10-15."


def test_etl_script_execution_2023_10_16():
    lines = _run_and_read_lines("2023-10-16")
    expected_lines = [
        "customer_id,customer_name,total_spent",
        "1,Alice Smith,15.50",
    ]
    assert lines == expected_lines, "Report contents do not match expected output for 2023-10-16."


def test_etl_on_unpredictable_database_fixture_and_observe_parameterization():
    conn = sqlite3.connect(DB_PATH)

    # Select an unused, valid date at verification time so fixed-date output cannot pass.
    for _ in range(1000):
        date_arg = f"{random.randint(2040, 2098):04d}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
        if conn.execute("SELECT 1 FROM orders WHERE order_date=? LIMIT 1", (date_arg,)).fetchone() is None:
            break
    else:
        raise AssertionError("Could not find an unused verification date")

    suffix = random.randint(100000, 999999)
    c1 = conn.execute(
        "INSERT INTO customers(name,email) VALUES (?,?)",
        (f"Verifier, Customer {suffix}", f"verify{suffix}@example.invalid"),
    ).lastrowid
    c2 = conn.execute(
        "INSERT INTO customers(name,email) VALUES (?,?)",
        (f"Second Customer {suffix}", f"second{suffix}@example.invalid"),
    ).lastrowid
    o1 = conn.execute("INSERT INTO orders(customer_id,order_date) VALUES (?,?)", (c1, date_arg)).lastrowid
    o2 = conn.execute("INSERT INTO orders(customer_id,order_date) VALUES (?,?)", (c1, date_arg)).lastrowid
    o3 = conn.execute("INSERT INTO orders(customer_id,order_date) VALUES (?,?)", (c2, date_arg)).lastrowid
    conn.executemany(
        "INSERT INTO order_items(order_id,product_id,quantity,unit_price) VALUES (?,?,?,?)",
        [
            (o1, 7001, 2, 3.25),
            (o1, 7002, 1, 1.50),
            (o2, 7003, 4, 2.00),
            (o3, 7004, 3, 4.25),
        ],
    )
    conn.commit()

    oracle_rows = conn.execute(
        """
        SELECT c.id, c.name, printf('%.2f', SUM(oi.quantity * oi.unit_price))
        FROM customers AS c
        JOIN orders AS o ON o.customer_id = c.id
        JOIN order_items AS oi ON oi.order_id = o.id
        WHERE o.order_date = ?
        GROUP BY c.id, c.name
        ORDER BY c.id
        """,
        (date_arg,),
    ).fetchall()
    conn.close()

    # Temporarily wrap the real CLI to verify that the executed query itself uses
    # a bound placeholder and that the ETL makes one sqlite3 invocation.
    sqlite_path = shutil.which("sqlite3")
    assert sqlite_path, "sqlite3 is not installed."
    real_path = sqlite_path + ".__verifier_real"
    trace_path = "/tmp/sqlite_etl_trace.txt"
    if os.path.exists(trace_path):
        os.remove(trace_path)
    os.rename(sqlite_path, real_path)
    wrapper = f'''#!/bin/bash
set -e
tmp=$(mktemp)
cat > "$tmp"
{{
  echo '===INVOCATION==='
  for arg in "$@"; do printf 'ARG<<%s>>\\n' "$arg"; done
  echo '===STDIN==='
  cat "$tmp"
}} >> "{trace_path}"
"{real_path}" "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit $status
'''
    try:
        with open(sqlite_path, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)

        report_path = f"/home/user/report_{date_arg}.csv"
        if os.path.exists(report_path):
            os.remove(report_path)
        result = subprocess.run([SCRIPT_PATH, date_arg], capture_output=True, text=True)
        assert result.returncode == 0, f"Execution on dynamic fixture failed: {result.stderr}"
        assert os.path.isfile(report_path), f"Report file {report_path} was not created."
    finally:
        if os.path.exists(sqlite_path):
            os.remove(sqlite_path)
        os.rename(real_path, sqlite_path)

    with open(report_path, newline="") as f:
        actual = list(csv.reader(f))
    expected = [["customer_id", "customer_name", "total_spent"]] + [
        [str(customer_id), name, total] for customer_id, name, total in oracle_rows
    ]
    assert actual == expected, f"Dynamic report mismatch: expected {expected}, got {actual}"
    assert all(len(row) == 3 for row in actual), "CSV does not have exactly three columns."

    with open(trace_path, "r") as f:
        trace = f.read()
    assert trace.count("===INVOCATION===") == 1, "ETL must use one sqlite3 CLI invocation."
    trace_no_comments = re.sub(r"/\*.*?\*/|--[^\n]*", "", trace, flags=re.S)
    select = re.search(r"\bSELECT\b.*?;", trace_no_comments, flags=re.I | re.S)
    assert select, "No SQL SELECT query was passed to sqlite3."
    assert re.search(r"\?(?:\d+)?", select.group(0)), "Executed SELECT does not use a placeholder."
    assert date_arg not in select.group(0), "The date was concatenated directly into the SELECT text."
    assert re.search(r"\.parameter\s+set\s+\?(?:\d+)?(?:\s|$)", trace_no_comments, flags=re.I), (
        "The executed sqlite3 input does not bind the positional parameter."
    )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
