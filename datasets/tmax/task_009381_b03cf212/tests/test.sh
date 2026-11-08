#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from collections import defaultdict

import pytest

SCRIPT_PATH = "/home/user/process_data.sh"
REPORT_PATH = "/home/user/report.json"
PRODUCTS_PATH = "/home/user/products.csv"
TRANSACTIONS_PATH = "/home/user/transactions.csv"


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT_PATH), "Script did not generate /home/user/report.json"


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_report_json_exists_and_valid():
    run_script()
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    data = load_report()

    assert isinstance(data, list), "Root JSON element should be a list"
    assert len(data) == 2, f"Expected exactly 2 categories, found {len(data)}"

    # Check first category (Clothing)
    cat1 = data[0]
    assert cat1.get("category") == "Clothing", f"Expected first category to be 'Clothing', got {cat1.get('category')}"

    top_products_1 = cat1.get("top_products", [])
    assert len(top_products_1) == 2, "Expected 2 top products for Clothing"

    assert top_products_1[0].get("rank") == 1
    assert top_products_1[0].get("product_name") == "Jacket"
    assert float(top_products_1[0].get("total_amount")) == 100.0

    assert top_products_1[1].get("rank") == 2
    assert top_products_1[1].get("product_name") == "Jeans"
    assert float(top_products_1[1].get("total_amount")) == 100.0

    # Check second category (Electronics)
    cat2 = data[1]
    assert cat2.get("category") == "Electronics", f"Expected second category to be 'Electronics', got {cat2.get('category')}"

    top_products_2 = cat2.get("top_products", [])
    assert len(top_products_2) == 2, "Expected 2 top products for Electronics"

    assert top_products_2[0].get("rank") == 1
    assert top_products_2[0].get("product_name") == "Laptop"
    assert float(top_products_2[0].get("total_amount")) == 2000.0

    assert top_products_2[1].get("rank") == 2
    assert top_products_2[1].get("product_name") == "Smartphone"
    assert float(top_products_2[1].get("total_amount")) == 1600.0


def test_script_processes_changed_csv_inputs():
    token = secrets.token_hex(6)
    categories = [f"A_{token}", f"B_{token}", f"C_{token}", f"D_{token}"]
    products = [
        (1101, categories[0], f"AOne_{token}"),
        (1102, categories[0], f"ATwo_{token}"),
        (2101, categories[1], f"Zebra_{token}"),
        (2102, categories[1], f"Alpha_{token}"),
        (2103, categories[1], f"Middle_{token}"),
        (3101, categories[2], f"High_{token}"),
        (3102, categories[2], f"Next_{token}"),
        (3103, categories[2], f"Low_{token}"),
        (4101, categories[3], f"DOne_{token}"),
        (4102, categories[3], f"DTwo_{token}"),
    ]
    transactions = [
        (1, 1101, "2025-01-01", 7.25),
        (2, 1102, "2025-01-02", 9.50),
        (3, 2101, "2025-01-03", 20.00),
        (4, 2101, "2025-01-04", 30.00),
        (5, 2102, "2025-01-05", 50.00),
        (6, 2103, "2025-01-06", 10.00),
        (7, 3101, "2025-01-07", 25.00),
        (8, 3101, "2025-01-08", 45.00),
        (9, 3102, "2025-01-09", 40.00),
        (10, 3103, "2025-01-10", 5.00),
        (11, 4101, "2025-01-11", 100.00),
        (12, 4102, "2025-01-12", 80.00),
    ]

    with open(PRODUCTS_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["product_id", "category", "product_name"])
        writer.writerows(products)

    with open(TRANSACTIONS_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["tx_id", "product_id", "tx_date", "amount"])
        writer.writerows(transactions)

    product_info = {pid: (category, name) for pid, category, name in products}
    totals = defaultdict(float)
    for _, product_id, _, amount in transactions:
        totals[product_id] += amount

    grouped = defaultdict(list)
    for product_id, total in totals.items():
        category, name = product_info[product_id]
        grouped[category].append((name, total))

    expected = []
    for category in sorted(grouped)[1:3]:
        ranked = sorted(grouped[category], key=lambda item: (-item[1], item[0]))[:2]
        expected.append({
            "category": category,
            "top_products": [
                {"rank": rank, "product_name": name, "total_amount": total}
                for rank, (name, total) in enumerate(ranked, 1)
            ],
        })

    run_script()
    actual = load_report()
    assert actual == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
