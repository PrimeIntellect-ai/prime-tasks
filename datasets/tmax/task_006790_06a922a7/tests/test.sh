#!/bin/bash
mkdir -p /logs/verifier

if cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import csv
import re
import secrets
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_analysis.sh"
OUTPUT_PATH = "/home/user/output/active_orders.json"
DB_PATH = "/home/user/data/sales.sqlite"
CSV_PATH = "/home/user/data/customers.csv"

@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular file."

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        script = f.read()

    window_call = re.search(
        r"\b(?:row_number|rank|dense_rank|first_value|last_value|max|min)\s*\([^)]*\)\s*over\s*\(",
        script,
        flags=re.IGNORECASE | re.DOTALL,
    )
    assert window_call, "The script must use a SQL window function to isolate the latest order rows."
    assert re.search(r"\bpartition\s+by\b[^;]*\border_id\b", script, re.IGNORECASE | re.DOTALL), \
        "The SQL window must partition orders by order_id."
    assert re.search(r"\border\s+by\b[^;]*\bupdated_at\b[^;]*\bdesc\b", script, re.IGNORECASE | re.DOTALL), \
        "The SQL window must order by updated_at descending."

    # Add unpredictable records before execution so a precomputed JSON file or a
    # script that merely emits the original fixture cannot pass.
    conn = sqlite3.connect(DB_PATH)
    used_order_ids = {row[0] for row in conn.execute("SELECT order_id FROM order_history")}
    while True:
        base = 1_000_000_000 + secrets.randbelow(500_000_000)
        if base not in used_order_ids and base + 1 not in used_order_ids:
            break

    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        existing_customers = list(csv.DictReader(f))
    used_customer_ids = {int(row["customer_id"]) for row in existing_customers}
    while True:
        customer_id = 1_000_000 + secrets.randbelow(500_000)
        if customer_id not in used_customer_ids:
            break

    with open(CSV_PATH, "a", encoding="utf-8", newline="") as f:
        csv.writer(f).writerow([customer_id, "Verifier", "Customer", "TestRegion"])

    amount = float(1000 + secrets.randbelow(8000)) + 0.25
    conn.executemany(
        """INSERT INTO order_history
           (order_id, customer_id, amount, status, updated_at)
           VALUES (?, ?, ?, ?, ?)""",
        [
            (base, customer_id, amount - 10, "PENDING", "2098-01-01 00:00:00"),
            (base, customer_id, amount, "SHIPPED", "2099-01-01 00:00:00"),
            (base + 1, customer_id, amount + 20, "SHIPPED", "2098-02-01 00:00:00"),
            (base + 1, customer_id, amount + 20, "CANCELLED", "2099-02-01 00:00:00"),
        ],
    )
    conn.commit()
    conn.close()

    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            pytest.fail(f"{OUTPUT_PATH} is a directory, not a JSON output file.")
        os.unlink(OUTPUT_PATH)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}:\n{result.stdout}"


def get_expected_data():
    db_path = "/home/user/data/sales.sqlite"
    csv_path = "/home/user/data/customers.csv"

    # Read customers
    customers = {}
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            customers[int(row["customer_id"])] = {
                "customer_id": int(row["customer_id"]),
                "full_name": f"{row['first_name']} {row['last_name']}",
                "region": row["region"],
                "active_orders": []
            }

    # Read orders
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Window function to get latest order
    query = """
    WITH RankedOrders AS (
        SELECT
            order_id,
            customer_id,
            amount,
            status,
            ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY updated_at DESC) as rn
        FROM order_history
    )
    SELECT order_id, customer_id, amount, status
    FROM RankedOrders
    WHERE rn = 1 AND status != 'CANCELLED'
    """

    cursor.execute(query)
    for row in cursor.fetchall():
        cid = row["customer_id"]
        if cid in customers:
            customers[cid]["active_orders"].append({
                "order_id": row["order_id"],
                "amount": float(row["amount"]),
                "status": row["status"]
            })

    conn.close()

    # Format output
    final_customers = []
    for cid in sorted(customers.keys()):
        if customers[cid]["active_orders"]:
            customers[cid]["active_orders"].sort(key=lambda x: x["order_id"])
            final_customers.append(customers[cid])

    return {"customers": final_customers}


def test_output_file_exists():
    output_path = "/home/user/output/active_orders.json"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."


def test_output_json_content():
    output_path = "/home/user/output/active_orders.json"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r", encoding="utf-8") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {output_path}: {e}")

    expected_data = get_expected_data()

    assert "customers" in actual_data, "The JSON object must have a 'customers' key."

    # Compare structure
    assert len(actual_data["customers"]) == len(expected_data["customers"]), \
        f"Expected {len(expected_data['customers'])} customers, but got {len(actual_data['customers'])}."

    for expected_c, actual_c in zip(expected_data["customers"], actual_data["customers"]):
        assert actual_c.get("customer_id") == expected_c["customer_id"], "Customer ID mismatch or missing."
        assert actual_c.get("full_name") == expected_c["full_name"], "Full name mismatch or missing."
        assert actual_c.get("region") == expected_c["region"], "Region mismatch or missing."

        expected_orders = expected_c["active_orders"]
        actual_orders = actual_c.get("active_orders", [])

        assert len(actual_orders) == len(expected_orders), \
            f"Expected {len(expected_orders)} active orders for customer {expected_c['customer_id']}, got {len(actual_orders)}."

        for expected_o, actual_o in zip(expected_orders, actual_orders):
            assert actual_o.get("order_id") == expected_o["order_id"], "Order ID mismatch."
            assert actual_o.get("status") == expected_o["status"], "Order status mismatch."
            # Allow some float tolerance or exact match
            assert float(actual_o.get("amount", 0)) == float(expected_o["amount"]), "Order amount mismatch."
TEST_EOF
then
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        echo "1" > /logs/verifier/reward.txt
    else
        echo "0" > /logs/verifier/reward.txt
    fi
else
    echo "0" > /logs/verifier/reward.txt
fi
