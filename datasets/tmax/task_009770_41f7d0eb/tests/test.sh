#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import sqlite3
import subprocess
import time
import uuid
from contextlib import contextmanager

DB_PATH = "/home/user/ecommerce.db"
SCRIPT_PATH = "/home/user/get_orders.sh"
SQLITE_PATH = "/usr/bin/sqlite3"


def run_script(*args, timeout=10):
    return subprocess.run(
        [SCRIPT_PATH, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def parse_csv_output(output):
    return list(csv.reader(io.StringIO(output)))


def assert_rows_match(output, expected):
    rows = parse_csv_output(output)
    assert rows, "Script produced no CSV output."
    assert rows[0] == ["order_id", "order_date", "amount"], "CSV header is incorrect."
    assert len(rows) == len(expected) + 1, "CSV row count is incorrect."
    for actual, wanted in zip(rows[1:], expected):
        assert len(actual) == 3, "A CSV data row does not have exactly three fields."
        assert actual[0] == wanted[0]
        assert actual[1] == wanted[1]
        assert float(actual[2]) == float(wanted[2])


@contextmanager
def capture_sqlite_cli():
    """Temporarily wrap the real CLI so its commands can be audited."""
    backup = SQLITE_PATH + ".verifier-real"
    log_path = f"/tmp/sqlite-cli-{uuid.uuid4().hex}.log"
    assert os.path.isfile(SQLITE_PATH), "sqlite3 CLI is missing."
    assert not os.path.exists(backup), f"Unexpected file exists: {backup}"

    os.rename(SQLITE_PATH, backup)
    wrapper = f'''#!/bin/bash
_tmp=$(mktemp)
cat > "$_tmp"
{{
  printf '%s\\n' "$@"
  printf '%s\\n' '---STDIN---'
  cat "$_tmp"
  printf '%s\\n' '---END---'
}} >> {log_path!r}
{backup!r} "$@" < "$_tmp"
_rc=$?
rm -f "$_tmp"
exit $_rc
'''
    with open(SQLITE_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(SQLITE_PATH, 0o755)
    try:
        yield log_path
    finally:
        try:
            os.remove(SQLITE_PATH)
        finally:
            os.rename(backup, SQLITE_PATH)


def test_index_exists_and_optimizes_query():
    """Verify that a covering index prevents scans and temporary sorting."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    query = "EXPLAIN QUERY PLAN SELECT order_id, order_date, amount FROM orders WHERE customer_id = 'CUST_A' AND status = 'SHIPPED' ORDER BY order_date DESC;"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(query)
    plan = cursor.fetchall()

    # Confirm that an actual index has the filtering/sort prefix and covers all
    # projected columns, rather than accepting any unrelated SEARCH plan.
    cursor.execute("PRAGMA index_list('orders')")
    indexes = cursor.fetchall()
    suitable = []
    for index_row in indexes:
        name = index_row[1]
        cursor.execute(f"PRAGMA index_xinfo('{name.replace(chr(39), chr(39) * 2)}')")
        key_columns = [row[2] for row in cursor.fetchall() if row[5] == 1 and row[2] is not None]
        if (key_columns[:3] == ["customer_id", "status", "order_date"] and
                "order_id" in key_columns[3:] and "amount" in key_columns[3:]):
            suitable.append(name)
    conn.close()

    plan_text = " ".join([row[-1] for row in plan]).upper()

    # Preserve the original assertions.
    assert "SEARCH" in plan_text, "The query plan does not use an index (SEARCH missing)."
    assert "SCAN" not in plan_text, "The query plan still performs a full table SCAN."

    assert suitable, "No index has the required filter/order prefix and covering columns."
    assert "COVERING INDEX" in plan_text, f"The selected query plan is not covering: {plan_text}"
    assert "TEMP B-TREE" not in plan_text, f"The query still requires a temporary sort: {plan_text}"


def test_script_exists_and_executable():
    """Verify the bash script exists and has executable permissions."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_output_and_pagination():
    """Preserve the original fixed-result checks."""
    result1 = run_script("CUST_A", "SHIPPED", "1", "0")
    assert result1.returncode == 0, "Script failed with offset 0."
    expected_output1 = "order_id,order_date,amount\nORD003,2023-10-03T12:00:00Z,99.99\n"
    assert result1.stdout.strip() == expected_output1.strip(), "Script output mismatch for offset 0."

    result2 = run_script("CUST_A", "SHIPPED", "1", "1")
    assert result2.returncode == 0, "Script failed with offset 1."
    expected_output2 = "order_id,order_date,amount\nORD001,2023-10-01T10:00:00Z,150.5\n"
    assert result2.stdout.strip() in (expected_output2.strip(), expected_output2.strip() + "0"), "Script output mismatch for offset 1."


def test_script_integer_validation():
    """Verify limit and offset validation and the exact argument count."""
    result = run_script("CUST_A", "SHIPPED", "1 DROP TABLE orders;", "0")
    assert result.returncode != 0, "Script did not fail when given a non-integer limit."

    assert run_script("CUST_A", "SHIPPED", "1", "not-an-int").returncode != 0
    assert run_script("CUST_A", "SHIPPED", "1").returncode != 0
    assert run_script("CUST_A", "SHIPPED", "1", "0", "extra").returncode != 0


def test_script_contains_timeout():
    """Preserve the original timeout-content assertion."""
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read().lower()
    assert "timeout" in content, "Script does not contain timeout configuration."


def test_general_queries_secure_binding_and_cli_configuration():
    """Exercise unpredictable data and audit the commands sent to sqlite3."""
    token = uuid.uuid4().hex
    prefix = f"VERIFY_{token}_"
    quoted_customer = f"CUST_'_{token}"
    injection_status = f"PENDING' OR 1=1 -- {token}"
    normal_customer = f"CUSTOMER_{token}"
    normal_status = f"STATUS_{token}"

    inserted = []
    for i in range(18):
        customer = quoted_customer if i < 11 else normal_customer
        status = injection_status if i % 3 != 0 else normal_status
        order_id = prefix + (f"ORDER,{i}" if i == 5 else f"ORDER_{i}")
        order_date = f"2042-07-{1 + i:02d}T12:34:{i:02d}Z"
        amount = float(1000 + i) + 0.25
        inserted.append((order_id, customer, order_date, status, amount))

    # Decoys ensure that ignoring either filter returns incorrect data.
    inserted.extend([
        (prefix + "DECOY_A", quoted_customer, "2099-01-01T00:00:00Z", normal_status, 9001.5),
        (prefix + "DECOY_B", normal_customer, "2099-01-02T00:00:00Z", injection_status, 9002.5),
    ])

    conn = sqlite3.connect(DB_PATH)
    conn.executemany("INSERT INTO orders VALUES (?, ?, ?, ?, ?)", inserted)
    conn.commit()

    cases = [
        (quoted_customer, injection_status, 1, 0),
        (quoted_customer, injection_status, 4, 1),
        (quoted_customer, injection_status, 20, 2),
        (normal_customer, normal_status, 3, 0),
        (normal_customer, injection_status, 2, 1),
        (quoted_customer, injection_status, 0, 0),
        (quoted_customer, injection_status, 5, 100),
    ]

    try:
        with capture_sqlite_cli() as log_path:
            for customer, status, limit, offset in cases:
                expected = conn.execute(
                    "SELECT order_id, order_date, amount FROM orders "
                    "WHERE customer_id = ? AND status = ? "
                    "ORDER BY order_date DESC LIMIT ? OFFSET ?",
                    (customer, status, limit, offset),
                ).fetchall()
                result = run_script(customer, status, str(limit), str(offset))
                assert result.returncode == 0, result.stderr
                assert_rows_match(result.stdout, expected)

            assert os.path.exists(log_path), "The script did not invoke the sqlite3 CLI."
            transcript = open(log_path).read()

        assert re.search(r"(?im)^\s*\.timeout\s+5000(?:\s|$)", transcript), (
            "The commands actually sent to sqlite3 did not configure .timeout 5000."
        )

        token_pattern = r"(?:[?][0-9]+|[:@$][A-Za-z_][A-Za-z0-9_]*)"
        customer_match = re.search(
            rf"customer_id\s*=\s*({token_pattern})", transcript, re.IGNORECASE
        )
        status_match = re.search(
            rf"status\s*=\s*({token_pattern})", transcript, re.IGNORECASE
        )
        assert customer_match and status_match, (
            "The executed SQL must compare customer_id and status to bound parameters."
        )
        for parameter in (customer_match.group(1), status_match.group(1)):
            assert re.search(
                rf"(?im)^\s*\.parameter\s+set\s+{re.escape(parameter)}(?:\s|$)",
                transcript,
            ), f"No sqlite3 .parameter set command was executed for {parameter}."

        # The injection-like value must remain data and must not alter the table.
        count = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
        assert count >= len(inserted), "The orders table was modified by an argument value."
    finally:
        try:
            conn.execute("DELETE FROM orders WHERE order_id LIKE ?", (prefix + "%",))
            conn.commit()
        finally:
            conn.close()


def test_busy_timeout_works_under_lock():
    """Ensure a real read waits for a transient exclusive lock and then succeeds."""
    locker = sqlite3.connect(DB_PATH, timeout=1)
    process = None
    try:
        locker.execute("BEGIN EXCLUSIVE")
        started = time.monotonic()
        process = subprocess.Popen(
            [SCRIPT_PATH, "CUST_A", "SHIPPED", "1", "0"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.6)
        assert process.poll() is None, "The script failed immediately instead of waiting on the lock."
        locker.rollback()
        stdout, stderr = process.communicate(timeout=6)
        elapsed = time.monotonic() - started
        assert process.returncode == 0, stderr
        assert elapsed >= 0.5
        assert_rows_match(stdout, [("ORD003", "2023-10-03T12:00:00Z", 99.99)])
    finally:
        if locker.in_transaction:
            locker.rollback()
        locker.close()
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
