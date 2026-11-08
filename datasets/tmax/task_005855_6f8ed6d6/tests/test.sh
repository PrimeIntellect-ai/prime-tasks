#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess
from decimal import Decimal

import jsonschema
import pytest

BASE = '/home/user'
SCRIPT = os.path.join(BASE, 'process_sales.py')
SUMMARY = os.path.join(BASE, 'summary.json')
INPUTS = ['customers.csv', 'orders.csv', 'items.csv']


def _run_script():
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'process_sales.py exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(SUMMARY), 'process_sales.py did not generate /home/user/summary.json'


def _expected_from_csvs():
    with open(os.path.join(BASE, 'customers.csv'), newline='') as f:
        customers = {row['customer_id']: row['name'] for row in csv.DictReader(f)}
    with open(os.path.join(BASE, 'orders.csv'), newline='') as f:
        orders = {row['order_id']: row['customer_id'] for row in csv.DictReader(f)}

    totals = {}
    with open(os.path.join(BASE, 'items.csv'), newline='') as f:
        for row in csv.DictReader(f):
            customer_id = orders.get(row['order_id'])
            if customer_id in customers:
                name = customers[customer_id]
                totals[name] = totals.get(name, Decimal('0')) + Decimal(row['price'])
    return {name: float(amount.quantize(Decimal('0.01'))) for name, amount in totals.items()}


def _load_and_check_summary(expected):
    with open(SUMMARY, 'r') as f:
        data = json.load(f)
    with open(os.path.join(BASE, 'schema.json'), 'r') as f:
        schema = json.load(f)
    jsonschema.validate(data, schema)

    assert isinstance(data, list)
    assert len(data) == len(expected), 'Summary has missing or duplicate/unexpected customer rows'
    actual = {}
    for item in data:
        assert isinstance(item, dict)
        assert set(item) == {'customer_name', 'total_spent'}
        assert isinstance(item['customer_name'], str)
        assert isinstance(item['total_spent'], (int, float)) and not isinstance(item['total_spent'], bool)
        assert item['customer_name'] not in actual, f"Duplicate customer: {item['customer_name']}"
        actual[item['customer_name']] = float(item['total_spent'])

    assert set(actual) == set(expected), f'Expected customers {set(expected)}, got {set(actual)}'
    for name, total in expected.items():
        assert abs(actual[name] - total) < 1e-9, (
            f'Incorrect total_spent for {name}: expected {total}, got {actual[name]}'
        )


def test_00_script_executes_and_recomputes_from_csv_inputs():
    assert os.path.exists(SCRIPT), f'File missing: {SCRIPT}'
    assert not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular Python file, not a symlink'
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f'{SCRIPT} is not a regular file'

    backups = {}
    for filename in INPUTS:
        path = os.path.join(BASE, filename)
        with open(path, 'rb') as f:
            backups[filename] = f.read()

    token = secrets.token_hex(8)
    names = [f'Customer_{token}_{i}' for i in range(1, 4)]
    prices = [
        Decimal(secrets.randbelow(8000) + 101) / 100,
        Decimal(secrets.randbelow(8000) + 101) / 100,
        Decimal(secrets.randbelow(8000) + 101) / 100,
        Decimal(secrets.randbelow(8000) + 101) / 100,
        Decimal(secrets.randbelow(8000) + 101) / 100,
    ]

    try:
        with open(os.path.join(BASE, 'customers.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['customer_id', 'name'])
            writer.writerows([[701, names[0]], [702, names[1]], [703, names[2]]])
        with open(os.path.join(BASE, 'orders.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['order_id', 'customer_id', 'date'])
            writer.writerows([
                [8101, 701, '2025-03-01'],
                [8102, 701, '2025-03-02'],
                [8103, 702, '2025-03-03'],
                [8104, 703, '2025-03-04'],
            ])
        with open(os.path.join(BASE, 'items.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['item_id', 'order_id', 'price'])
            writer.writerows([
                [9101, 8101, f'{prices[0]:.2f}'],
                [9102, 8101, f'{prices[1]:.2f}'],
                [9103, 8102, f'{prices[2]:.2f}'],
                [9104, 8103, f'{prices[3]:.2f}'],
                [9105, 8104, f'{prices[4]:.2f}'],
            ])

        if os.path.lexists(SUMMARY):
            os.remove(SUMMARY)
        expected = _expected_from_csvs()
        _run_script()
        _load_and_check_summary(expected)
    finally:
        for filename, content in backups.items():
            with open(os.path.join(BASE, filename), 'wb') as f:
                f.write(content)
        if os.path.lexists(SUMMARY):
            os.remove(SUMMARY)
        try:
            subprocess.run(
                ['python3', SCRIPT], cwd=BASE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=30
            )
        except Exception:
            pass


def test_summary_json_exists():
    path = '/home/user/summary.json'
    assert os.path.isfile(path), f"File missing: {path}. The script should generate this file."


def test_summary_json_content():
    path = '/home/user/summary.json'
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {path}")

    assert isinstance(data, list), f"The root of {path} should be a JSON array."

    results = {}
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."

        keys = set(item.keys())
        assert keys == {"customer_name", "total_spent"}, f"Item at index {i} has incorrect keys: {keys}. Expected exactly 'customer_name' and 'total_spent'."

        name = item["customer_name"]
        spent = item["total_spent"]

        assert isinstance(name, str), f"customer_name must be a string, got {type(name)} for {name}"
        assert isinstance(spent, (int, float)), f"total_spent must be a number, got {type(spent)} for {name}"

        results[name] = float(spent)

    assert "Alice" in results, "Missing customer 'Alice' in the summary."
    assert "Bob" in results, "Missing customer 'Bob' in the summary."

    assert abs(results["Alice"] - 40.5) < 1e-5, f"Incorrect total_spent for Alice. Expected 40.5, got {results['Alice']}"
    assert abs(results["Bob"] - 150.0) < 1e-5, f"Incorrect total_spent for Bob. Expected 150.0, got {results['Bob']}"

    if "Charlie" in results:
        assert abs(results["Charlie"] - 0.0) < 1e-5, f"Incorrect total_spent for Charlie. Expected 0.0, got {results['Charlie']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
