#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

ETL = "/home/user/etl"
MIGRATE = os.path.join(ETL, "migrate.py")
DB = os.path.join(ETL, "source.db")
OUTPUT = os.path.join(ETL, "output.jsonl")
REVENUE = os.path.join(ETL, "revenue_by_region.json")
AGG_PY = os.path.join(ETL, "aggregate.py")
AGG_JS = os.path.join(ETL, "aggregate.js")


def run(cmd):
    result = subprocess.run(cmd, cwd=ETL, text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def run_aggregate():
    failures = []
    if os.path.isfile(AGG_PY):
        result = subprocess.run(["python3", AGG_PY], cwd=ETL, text=True,
                                capture_output=True, timeout=20)
        if result.returncode == 0:
            return
        failures.append(f"python3 aggregate.py: {result.stderr}")
    if os.path.isfile(AGG_JS):
        assert shutil.which("node"), "aggregate.js exists, but Node.js is unavailable"
        result = subprocess.run(["node", AGG_JS], cwd=ETL, text=True,
                                capture_output=True, timeout=20)
        if result.returncode == 0:
            return
        failures.append(f"node aggregate.js: {result.stderr}")
    raise AssertionError("Aggregation script did not run successfully: " + " | ".join(failures))


def read_jsonl(path):
    assert os.path.isfile(path), f"The output file {path} does not exist."
    docs = []
    with open(path, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                docs.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Line {line_number} in {path} is not valid JSON: {exc}")
    return docs


def check_parameterization_source():
    assert os.path.isfile(MIGRATE), f"The script {MIGRATE} does not exist."
    with open(MIGRATE, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "?" in content or ":" in content or "%s" in content, (
        "The SQL query does not appear to use parameterization markers (e.g., '?')."
    )
    assert "f\"SELECT" not in content and "f'SELECT" not in content, (
        "The script still uses an f-string for the SELECT query."
    )

    # Require an execute/executemany call that actually supplies a parameter argument.
    tree = ast.parse(content, filename=MIGRATE)
    parameterized_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in ("execute", "executemany") and len(node.args) >= 2:
                parameterized_calls.append(node)
    assert parameterized_calls, "No database execute call supplies bound query parameters."


def check_fixed_outputs():
    docs = read_jsonl(OUTPUT)
    assert len(docs) == 3, f"Expected exactly 3 JSON objects in output.jsonl, found {len(docs)}."
    docs.sort(key=lambda x: x.get("customer_id", 0))

    expected = [
        {"customer_id": 1, "name": "Alice", "region": "North",
         "orders": [{"order_id": 101, "amount": 50.0}, {"order_id": 102, "amount": 25.5}]},
        {"customer_id": 2, "name": "Bob", "region": "South",
         "orders": [{"order_id": 103, "amount": 200.0}]},
        {"customer_id": 4, "name": "Diana", "region": "North",
         "orders": [{"order_id": 105, "amount": 75.0}]},
    ]

    for actual, wanted in zip(docs, expected):
        for key in ("customer_id", "name", "region", "orders"):
            assert key in actual, f"Missing '{key}' in JSON document."
        assert actual["customer_id"] == wanted["customer_id"]
        assert actual["name"] == wanted["name"]
        assert actual["region"] == wanted["region"]
        actual_orders = sorted(actual["orders"], key=lambda x: x.get("order_id", 0))
        wanted_orders = sorted(wanted["orders"], key=lambda x: x["order_id"])
        assert len(actual_orders) == len(wanted_orders)
        for actual_order, wanted_order in zip(actual_orders, wanted_orders):
            assert actual_order.get("order_id") == wanted_order["order_id"]
            assert float(actual_order.get("amount", 0)) == wanted_order["amount"]

    assert os.path.isfile(AGG_PY) or os.path.isfile(AGG_JS), (
        "The aggregation script (aggregate.py or aggregate.js) does not exist."
    )
    assert os.path.isfile(REVENUE), f"The output file {REVENUE} does not exist."
    with open(REVENUE, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, dict), "The revenue JSON must be a single JSON object."
    assert len(data) == 2, f"Expected exactly 2 regions, found {len(data)}."
    assert "North" in data
    assert "South" in data
    assert float(data["North"]) == 150.5
    assert float(data["South"]) == 200.0


def check_dynamic_migration():
    fd, backup = tempfile.mkstemp(prefix="source-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB, backup)
    marker = uuid.uuid4().hex
    test_date = f"2099-{marker[:2]}-{marker[2:4]}-{marker[4:10]}"

    try:
        conn = sqlite3.connect(DB)
        max_customer = conn.execute("SELECT COALESCE(MAX(id), 0) FROM customers").fetchone()[0]
        max_order = conn.execute("SELECT COALESCE(MAX(id), 0) FROM orders").fetchone()[0]
        new_customer = max_customer + 101
        no_order_customer = max_customer + 102
        existing_customer = conn.execute("SELECT id FROM customers ORDER BY id LIMIT 1").fetchone()[0]
        conn.execute("INSERT INTO customers VALUES (?, ?, ?)",
                     (new_customer, "Quoted ' Customer " + marker[:6], "Dynamic-" + marker[:8]))
        conn.execute("INSERT INTO customers VALUES (?, ?, ?)",
                     (no_order_customer, "No Orders " + marker[:6], "Unused-" + marker[:8]))
        conn.executemany("INSERT INTO orders VALUES (?, ?, ?, ?)", [
            (max_order + 101, new_customer, 12.75, test_date),
            (max_order + 102, new_customer, 3.5, test_date),
            (max_order + 103, existing_customer, 8.125, test_date),
            (max_order + 104, no_order_customer, 999.0, test_date + "-other"),
        ])
        conn.commit()

        rows = conn.execute(
            "SELECT c.id, c.name, c.region, o.id, o.amount "
            "FROM customers c JOIN orders o ON c.id = o.customer_id "
            "WHERE o.date = ? ORDER BY c.id, o.id", (test_date,)
        ).fetchall()
        expected = {}
        for customer_id, name, region, order_id, amount in rows:
            expected.setdefault(customer_id, {
                "customer_id": customer_id, "name": name, "region": region, "orders": []
            })["orders"].append({"order_id": order_id, "amount": float(amount)})
        conn.close()

        run(["python3", MIGRATE, test_date])
        actual_docs = read_jsonl(OUTPUT)
        assert len(actual_docs) == len(expected)
        actual_by_id = {}
        for doc in actual_docs:
            assert set(doc) == {"customer_id", "name", "region", "orders"}, (
                "Each migrated document must have exactly the required schema."
            )
            assert isinstance(doc["orders"], list) and doc["orders"]
            assert doc["customer_id"] not in actual_by_id, "Expected one document per customer."
            for order in doc["orders"]:
                assert set(order) == {"order_id", "amount"}
            actual_by_id[doc["customer_id"]] = doc

        assert set(actual_by_id) == set(expected)
        for customer_id, wanted in expected.items():
            actual = actual_by_id[customer_id]
            assert actual["name"] == wanted["name"]
            assert actual["region"] == wanted["region"]
            actual_orders = sorted(actual["orders"], key=lambda x: x["order_id"])
            wanted_orders = sorted(wanted["orders"], key=lambda x: x["order_id"])
            assert len(actual_orders) == len(wanted_orders)
            for got, exp in zip(actual_orders, wanted_orders):
                assert got["order_id"] == exp["order_id"]
                assert math.isclose(float(got["amount"]), exp["amount"], rel_tol=0, abs_tol=1e-9)

        # A bound parameter treats this as literal data rather than SQL syntax.
        run(["python3", MIGRATE, test_date + "' OR 1=1 --"])
        assert read_jsonl(OUTPUT) == [], "The date filter appears vulnerable to SQL injection."
    finally:
        shutil.copy2(backup, DB)
        os.unlink(backup)


def check_dynamic_aggregation():
    marker = uuid.uuid4().hex[:10]
    region_a = "Region-A-" + marker
    region_b = "Region-B-" + marker
    docs = [
        {"customer_id": 7001, "name": "One", "region": region_a,
         "orders": [{"order_id": 8001, "amount": 1.25}, {"order_id": 8002, "amount": 2.5}]},
        {"customer_id": 7002, "name": "Two", "region": region_a,
         "orders": [{"order_id": 8003, "amount": 10.125}]},
        {"customer_id": 7003, "name": "Three", "region": region_b,
         "orders": [{"order_id": 8004, "amount": 7.75}, {"order_id": 8005, "amount": -0.5}]},
    ]
    with open(OUTPUT, "w", encoding="utf-8") as f:
        for doc in docs:
            f.write(json.dumps(doc) + "\n")

    expected = {}
    for doc in docs:
        expected.setdefault(doc["region"], 0.0)
        expected[doc["region"]] += sum(float(order["amount"]) for order in doc["orders"])

    run_aggregate()
    assert os.path.isfile(REVENUE)
    with open(REVENUE, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert isinstance(actual, dict)
    assert set(actual) == set(expected)
    for region, total in expected.items():
        assert math.isclose(float(actual[region]), total, rel_tol=0, abs_tol=1e-9)


def main():
    check_parameterization_source()

    # Generate the required fixed artifacts by executing both submitted scripts.
    run(["python3", MIGRATE, "2023-10-01"])
    run_aggregate()
    check_fixed_outputs()

    # Exercise both artifacts on verifier-generated data and independently derived answers.
    check_dynamic_migration()
    check_dynamic_aggregation()


if __name__ == "__main__":
    main()
PY_EOF

(
    set -e
    python3 /tmp/test_final_state.py
)
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
