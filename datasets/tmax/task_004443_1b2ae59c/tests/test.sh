#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import subprocess
import uuid
from collections import defaultdict
from decimal import Decimal

SCRIPT_PATH = '/home/user/generate_report.sh'
PRODUCTS_PATH = '/home/user/data/products.csv'
SALES_PATH = '/home/user/data/sales.csv'


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def run_script_and_parse_json(category, page):
    result = subprocess.run(
        [SCRIPT_PATH, category, str(page)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, f"Script output is not valid JSON. Output: {result.stdout}"

    return data


def test_clothing_page_2():
    data = run_script_and_parse_json("Clothing", 2)

    assert data.get("category") == "Clothing", "Expected category 'Clothing'."
    assert data.get("page") == 2, "Expected page 2."

    results = data.get("results", [])
    assert len(results) == 2, f"Expected exactly 2 results on page 2, got {len(results)}."

    assert results[0] == {
        "rank": 3,
        "product_id": 5,
        "name": "Shirt",
        "total_revenue": 200
    }, f"First result on page 2 is incorrect. Got: {results[0]}"

    assert results[1] == {
        "rank": 3,
        "product_id": 7,
        "name": "Jacket",
        "total_revenue": 200
    }, f"Second result on page 2 is incorrect. Got: {results[1]}"


def test_electronics_page_1():
    data = run_script_and_parse_json("Electronics", 1)

    assert data.get("category") == "Electronics", "Expected category 'Electronics'."
    assert data.get("page") == 1, "Expected page 1."

    results = data.get("results", [])
    assert len(results) == 2, f"Expected exactly 2 results on page 1, got {len(results)}."

    assert results[0] == {
        "rank": 1,
        "product_id": 1,
        "name": "Laptop",
        "total_revenue": 4000
    }, f"First result on page 1 is incorrect. Got: {results[0]}"

    assert results[1] == {
        "rank": 2,
        "product_id": 2,
        "name": "Smartphone",
        "total_revenue": 3500
    }, f"Second result on page 1 is incorrect. Got: {results[1]}"


def test_clothing_page_3():
    data = run_script_and_parse_json("Clothing", 3)

    assert data.get("category") == "Clothing", "Expected category 'Clothing'."
    assert data.get("page") == 3, "Expected page 3."

    results = data.get("results", [])
    assert len(results) == 2, f"Expected exactly 2 results on page 3, got {len(results)}."

    assert results[0] == {
        "rank": 3,
        "product_id": 8,
        "name": "Hat",
        "total_revenue": 200
    }, f"First result on page 3 is incorrect. Got: {results[0]}"

    assert results[1] == {
        "rank": 6,
        "product_id": 9,
        "name": "Socks",
        "total_revenue": 150
    }, f"Second result on page 3 is incorrect. Got: {results[1]}"


def compute_expected(category, page):
    products = {}
    with open(PRODUCTS_PATH, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            products[int(row['product_id'])] = (row['category'], row['name'])

    totals = defaultdict(Decimal)
    with open(SALES_PATH, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            product_id = int(row['product_id'])
            totals[product_id] += Decimal(row['quantity']) * Decimal(row['price'])

    rows = []
    for product_id, total in totals.items():
        product = products.get(product_id)
        if product and product[0] == category:
            rows.append((product_id, product[1], total))

    rows.sort(key=lambda row: (-row[2], row[0]))
    ranked = []
    previous_total = None
    current_rank = None
    for position, (product_id, name, total) in enumerate(rows, start=1):
        if previous_total is None or total != previous_total:
            current_rank = position
        previous_total = total
        revenue = int(total) if total == total.to_integral_value() else float(total)
        ranked.append({
            'rank': current_rank,
            'product_id': product_id,
            'name': name,
            'total_revenue': revenue,
        })

    start = (page - 1) * 2
    return {
        'category': category,
        'page': page,
        'results': ranked[start:start + 2],
    }


def test_generated_dataset_join_ranking_and_pagination():
    original_products = open(PRODUCTS_PATH, 'rb').read()
    original_sales = open(SALES_PATH, 'rb').read()

    rng = random.SystemRandom()
    token = uuid.uuid4().hex
    target_category = f"Generated_{token}"
    other_category = f"Other_{token}"
    product_ids = rng.sample(range(1000, 9000), 9)

    # Seven target products include several ties. Two unrelated products have
    # larger revenues, ensuring rank is computed within the requested category.
    target_revenues = [900, 700, 700, 400, 400, 400, 100]
    product_rows = []
    sales_rows = []
    transaction_id = rng.randrange(10000, 50000)

    for index, (product_id, revenue) in enumerate(zip(product_ids[:7], target_revenues)):
        product_rows.append([product_id, target_category, f"Generated product {token[:8]}-{index}"])
        first = revenue // 2
        second = revenue - first
        sales_rows.append([transaction_id, '2025-01-01', product_id, 1, first])
        transaction_id += 1
        sales_rows.append([transaction_id, '2025-01-02', product_id, 1, second])
        transaction_id += 1

    for index, (product_id, revenue) in enumerate(zip(product_ids[7:], [5000, 3000])):
        product_rows.append([product_id, other_category, f"Unrelated product {token[:8]}-{index}"])
        sales_rows.append([transaction_id, '2025-01-03', product_id, 1, revenue])
        transaction_id += 1

    rng.shuffle(product_rows)
    rng.shuffle(sales_rows)

    try:
        with open(PRODUCTS_PATH, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['product_id', 'category', 'name'])
            writer.writerows(product_rows)
        with open(SALES_PATH, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['transaction_id', 'date', 'product_id', 'quantity', 'price'])
            writer.writerows(sales_rows)

        pages = [1, 2, 3, 4, 5]
        rng.shuffle(pages)
        for page in pages:
            actual = run_script_and_parse_json(target_category, page)
            expected = compute_expected(target_category, page)
            assert actual == expected, f"Incorrect generated-data report for page {page}. Expected {expected}, got {actual}"
    finally:
        with open(PRODUCTS_PATH, 'wb') as f:
            f.write(original_products)
        with open(SALES_PATH, 'wb') as f:
            f.write(original_sales)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
