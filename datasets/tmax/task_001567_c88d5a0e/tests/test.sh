#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import json
import re
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/analyze_backup.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    with open(script_path, "r", errors="replace") as f:
        script = f.read()
    first_line = script.splitlines()[0] if script.splitlines() else ""
    assert re.match(r"^#!.*\bbash(?:\s|$)", first_line), "analyze_backup.sh must be a Bash script"
    assert re.search(r"\bsqlite3\b", script), "analyze_backup.sh must use the sqlite3 CLI"

def test_report_exists_and_valid_json():
    report_path = "/home/user/integrity_report.json"
    assert os.path.isfile(report_path), f"Report not found at {report_path}"
    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report is not valid JSON")

    assert "orphaned_orders_count" in data, "Missing 'orphaned_orders_count' in report"
    assert "orphaned_orders_amount" in data, "Missing 'orphaned_orders_amount' in report"
    assert "orphaned_payments_count" in data, "Missing 'orphaned_payments_count' in report"
    assert "orphaned_payments_amount" in data, "Missing 'orphaned_payments_amount' in report"

def test_report_content_matches_db():
    db_path = "/home/user/db_backup.sqlite"
    report_path = "/home/user/integrity_report.json"

    assert os.path.isfile(db_path), f"Database not found at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Calculate truth dynamically using PRAGMA foreign_key_check
    cursor.execute("PRAGMA foreign_key_check;")
    violations = cursor.fetchall()

    orphaned_orders_ids = [row[1] for row in violations if row[0] == 'orders']
    orphaned_payments_ids = [row[1] for row in violations if row[0] == 'payments']

    orders_count = len(orphaned_orders_ids)
    payments_count = len(orphaned_payments_ids)

    orders_amount = 0.0
    if orphaned_orders_ids:
        placeholders = ','.join('?' * len(orphaned_orders_ids))
        cursor.execute(f"SELECT SUM(amount) FROM orders WHERE id IN ({placeholders})", orphaned_orders_ids)
        orders_amount = cursor.fetchone()[0] or 0.0

    payments_amount = 0.0
    if orphaned_payments_ids:
        placeholders = ','.join('?' * len(orphaned_payments_ids))
        cursor.execute(f"SELECT SUM(amount) FROM payments WHERE id IN ({placeholders})", orphaned_payments_ids)
        payments_amount = cursor.fetchone()[0] or 0.0

    conn.close()

    with open(report_path, "r") as f:
        data = json.load(f)

    assert data["orphaned_orders_count"] == orders_count, f"Expected {orders_count} orphaned orders"
    assert float(data["orphaned_orders_amount"]) == pytest.approx(orders_amount, 0.01), "Orphaned orders amount mismatch"
    assert data["orphaned_payments_count"] == payments_count, f"Expected {payments_count} orphaned payments"
    assert float(data["orphaned_payments_amount"]) == pytest.approx(payments_amount, 0.01), "Orphaned payments amount mismatch"

    # Check formatting for 2 decimal places
    with open(report_path, "r") as f:
        raw_content = f.read()

    assert re.search(r'"orphaned_orders_amount"\s*:\s*\d+\.\d{2}(?!\d)', raw_content), "orphaned_orders_amount is not formatted to exactly 2 decimal places"
    assert re.search(r'"orphaned_payments_amount"\s*:\s*\d+\.\d{2}(?!\d)', raw_content), "orphaned_payments_amount is not formatted to exactly 2 decimal places"
TEST_EOF

run_and_test() {
    expected_db="$1"
    rm -f /home/user/integrity_report.json

    if ! runuser -u user -- timeout 30s /home/user/analyze_backup.sh; then
        return 1
    fi

    # Analysis must not alter the backup being inspected.
    if ! cmp -s "$expected_db" /home/user/db_backup.sqlite; then
        echo "analyze_backup.sh modified db_backup.sqlite" >&2
        return 1
    fi

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

ok=1
cp /home/user/db_backup.sqlite /tmp/original_db_backup.sqlite

# Execute and verify the submitted script against the original backup.
if ! run_and_test /tmp/original_db_backup.sqlite; then
    ok=0
fi

if [ -f /home/user/integrity_report.json ]; then
    cp /home/user/integrity_report.json /tmp/original_integrity_report.json
fi

# Build a second, unpredictable backup so a precomputed report cannot pass.
order_a=$(printf '%d.%02d' "$((20 + RANDOM % 80))" "$((RANDOM % 100))")
order_b=$(printf '%d.%02d' "$((100 + RANDOM % 100))" "$((RANDOM % 100))")
order_c=$(printf '%d.%02d' "$((200 + RANDOM % 100))" "$((RANDOM % 100))")
payment_a=$(printf '%d.%02d' "$((300 + RANDOM % 100))" "$((RANDOM % 100))")
payment_b=$(printf '%d.%02d' "$((400 + RANDOM % 100))" "$((RANDOM % 100))")

rm -f /tmp/variant_db_backup.sqlite
sqlite3 /tmp/variant_db_backup.sqlite <<SQL_EOF
PRAGMA foreign_keys = OFF;
CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT
);
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    amount REAL,
    FOREIGN KEY(customer_id) REFERENCES customers(id)
);
CREATE TABLE payments (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    amount REAL,
    FOREIGN KEY(order_id) REFERENCES orders(id)
);
INSERT INTO customers VALUES (11, 'Valid Customer'), (12, 'Another Customer');
INSERT INTO orders VALUES (201, 11, 10.00);
INSERT INTO orders VALUES (202, 901, $order_a);
INSERT INTO orders VALUES (203, 902, $order_b);
INSERT INTO orders VALUES (204, 903, $order_c);
INSERT INTO payments VALUES (3001, 201, 10.00);
INSERT INTO payments VALUES (3002, 202, 5.00);
INSERT INTO payments VALUES (3003, 9901, $payment_a);
INSERT INTO payments VALUES (3004, 9902, $payment_b);
PRAGMA foreign_keys = ON;
SQL_EOF

cp /tmp/variant_db_backup.sqlite /home/user/db_backup.sqlite
chown user:user /home/user/db_backup.sqlite
chmod 666 /home/user/db_backup.sqlite
cp /home/user/db_backup.sqlite /tmp/expected_variant_db.sqlite

if ! run_and_test /tmp/expected_variant_db.sqlite; then
    ok=0
fi

# Restore the original task artifacts after verification.
cp /tmp/original_db_backup.sqlite /home/user/db_backup.sqlite
chown user:user /home/user/db_backup.sqlite
chmod 777 /home/user/db_backup.sqlite
if [ -f /tmp/original_integrity_report.json ]; then
    cp /tmp/original_integrity_report.json /home/user/integrity_report.json
    chown user:user /home/user/integrity_report.json
else
    rm -f /home/user/integrity_report.json
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
