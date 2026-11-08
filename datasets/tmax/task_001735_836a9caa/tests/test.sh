#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import runpy
import stat
from pathlib import Path
from unittest import mock

import pandas as pd

SCRIPT = Path('/home/user/report_generator.py')
OUTPUT = Path('/home/user/customer_revenue_rank.csv')
CUSTOMERS = Path('/home/user/customers.csv')
ORDERS = Path('/home/user/orders.csv')
ITEMS = Path('/home/user/order_items.csv')


def run_script_and_capture_queries():
    assert SCRIPT.is_file(), f'The required script {SCRIPT} does not exist.'
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f'{SCRIPT} is not a regular file.'
    compile(SCRIPT.read_text(encoding='utf-8'), str(SCRIPT), 'exec')

    if OUTPUT.exists():
        OUTPUT.unlink()

    queries = []
    real_read_sql_query = pd.read_sql_query

    def capture_query(sql, *args, **kwargs):
        queries.append(str(sql))
        return real_read_sql_query(sql, *args, **kwargs)

    with mock.patch.object(pd, 'read_sql_query', new=capture_query):
        runpy.run_path(str(SCRIPT), run_name='__main__')

    assert OUTPUT.is_file(), f'The output CSV file {OUTPUT} does not exist. Did the script create it?'
    assert any(re.search(r'\bRANK\s*\(\s*\)\s*OVER\s*\(', query, re.IGNORECASE | re.DOTALL)
               for query in queries), (
        'The script must execute a SQL query that uses the RANK() window function.'
    )


def read_output():
    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        return list(csv.reader(f))


def write_csv(path, header, rows):
    with path.open('w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def derive_expected(customers, orders, items):
    valid_customers = {int(row[0]) for row in customers}
    order_customer = {int(row[0]): int(row[1]) for row in orders}
    customers_with_orders = {cid for cid in order_customer.values() if cid in valid_customers}
    totals = {cid: 0.0 for cid in customers_with_orders}

    for row in items:
        order_id = int(row[1])
        if order_id in order_customer and order_customer[order_id] in totals:
            totals[order_customer[order_id]] += float(row[3]) * int(row[4])

    ranked = []
    for customer_id, total in totals.items():
        rank = 1 + sum(1 for other_total in totals.values() if other_total > total)
        ranked.append((customer_id, total, rank))
    return sorted(ranked, key=lambda row: (row[2], row[0]))


def assert_dynamic_output(expected):
    rows = read_output()
    assert rows, 'The output CSV is empty.'
    assert rows[0] == ['customer_id', 'total_revenue', 'revenue_rank'], (
        f'Expected exactly three columns, but got {rows[0]}'
    )
    assert len(rows[1:]) == len(expected), (
        f'Expected {len(expected)} data rows, but got {len(rows[1:])}.'
    )

    actual = []
    for row in rows[1:]:
        assert len(row) == 3, f'Expected 3 columns per row, got {len(row)} in row: {row}'
        actual.append((int(row[0]), float(row[1]), int(row[2])))

    assert [(row[0], row[2]) for row in actual] == [(row[0], row[2]) for row in expected], (
        f'Customer ordering or RANK() results are incorrect. Expected {expected}, got {actual}'
    )
    for got, want in zip(actual, expected):
        assert math.isclose(got[1], want[1], rel_tol=1e-9, abs_tol=1e-9), (
            f'Incorrect total_revenue for customer {want[0]}: expected {want[1]}, got {got[1]}'
        )


def test_script_executes_sql_and_generates_correct_reports():
    saved_inputs = {path: path.read_bytes() for path in (CUSTOMERS, ORDERS, ITEMS)}
    saved_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        # Execute the submitted artifact on the original inputs before checking the
        # original verifier's assertions, so a pre-created CSV cannot pass.
        run_script_and_capture_queries()
        rows = read_output()

        assert len(rows) > 0, 'The output CSV is empty.'
        expected_header = ['customer_id', 'total_revenue', 'revenue_rank']
        assert rows[0] == expected_header, f'Expected header {expected_header}, but got {rows[0]}'

        data_rows = rows[1:]
        assert len(data_rows) == 3, (
            f'Expected exactly 3 data rows (excluding Charlie who has no orders), but got {len(data_rows)}.'
        )

        parsed_rows = []
        for row in data_rows:
            assert len(row) == 3, f'Expected 3 columns per row, got {len(row)} in row: {row}'
            parsed_rows.append((int(row[0]), float(row[1]), int(row[2])))

        expected_rows = [(2, 50.0, 1), (4, 50.0, 1), (1, 45.0, 3)]
        assert parsed_rows == expected_rows, (
            f'Output CSV data does not match expected results. Expected: {expected_rows}; got: {parsed_rows}. '
            'Ensure ordering is by revenue_rank ASC then customer_id ASC, and use RANK().'
        )

        # Replace the inputs with an unseen case and independently derive its answer.
        customers = [
            (10, 'A'), (20, 'B'), (30, 'C'), (40, 'No Orders'), (50, 'D')
        ]
        orders = [
            (201, 10, '2024-01-01'), (202, 10, '2024-01-02'),
            (203, 20, '2024-01-03'), (204, 30, '2024-01-04'),
            (205, 50, '2024-01-05')
        ]
        items = [
            (1, 201, 'P1', 7.5, 2), (2, 201, 'P2', 5.0, 1),
            (3, 202, 'P3', 10.0, 2), (4, 203, 'P4', 8.0, 5),
            (5, 204, 'P5', 2.5, 4), (6, 205, 'P6', 1.0, 5)
        ]

        write_csv(CUSTOMERS, ['customer_id', 'name'], customers)
        write_csv(ORDERS, ['order_id', 'customer_id', 'order_date'], orders)
        write_csv(ITEMS, ['item_id', 'order_id', 'product_id', 'price', 'quantity'], items)

        expected = derive_expected(customers, orders, items)
        run_script_and_capture_queries()
        assert_dynamic_output(expected)

    finally:
        for path, content in saved_inputs.items():
            path.write_bytes(content)
        if saved_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(saved_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
