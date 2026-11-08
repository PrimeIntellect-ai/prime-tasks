#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess
import sys
from collections import defaultdict

import pytest

DB_PATH = '/home/user/ecommerce.db'
REPORT_PATH = '/home/user/report.csv'
PIPELINE_PATH = '/home/user/pipeline.py'
TRACE_PATH = '/tmp/pipeline_sql_trace.json'

EXPECTED_CSV_DATA = [
    ['base_product_id', 'accessory_product_id', 'sale_date', 'daily_total', 'rolling_3d_avg'],
    ['B1', 'A1', '2023-10-01', '25.0', '25.0'],
    ['B1', 'A1', '2023-10-02', '20.0', '22.5'],
    ['B1', 'A1', '2023-10-03', '30.0', '25.0'],
    ['B1', 'A1', '2023-10-04', '10.0', '20.0'],
    ['B1', 'A2', '2023-10-01', '50.0', '50.0'],
    ['B1', 'A2', '2023-10-03', '60.0', '55.0'],
    ['B2', 'A3', '2023-10-01', '100.0', '100.0']
]


def read_csv():
    with open(REPORT_PATH, 'r', newline='', encoding='utf-8') as f:
        return list(csv.reader(f))


def test_01_report_csv_exists_and_content():
    """Retain the original fixed-fixture report assertions."""
    assert os.path.exists(REPORT_PATH), f"Output file missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"

    actual_data = read_csv()
    assert len(actual_data) > 0, "The report.csv file is empty"
    assert actual_data[0] == EXPECTED_CSV_DATA[0], f"Headers do not match expected. Got: {actual_data[0]}"
    assert len(actual_data) == len(EXPECTED_CSV_DATA), f"Expected {len(EXPECTED_CSV_DATA)} rows, got {len(actual_data)}"

    for i, (actual_row, expected_row) in enumerate(zip(actual_data[1:], EXPECTED_CSV_DATA[1:]), start=1):
        assert actual_row == expected_row, f"Row {i} mismatch. Expected: {expected_row}, Got: {actual_row}"


def build_expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    graph = conn.execute(
        "SELECT src_product_id, dst_product_id FROM product_graph WHERE relationship_type = ?",
        ('is_accessory_of',)
    ).fetchall()
    sales = conn.execute("SELECT product_id, sale_date, amount FROM sales").fetchall()
    conn.close()

    sales_by_product = defaultdict(list)
    for product_id, sale_date, amount in sales:
        sales_by_product[product_id].append((str(sale_date), float(amount)))

    daily = defaultdict(float)
    for accessory_id, base_id in graph:
        for sale_date, amount in sales_by_product.get(accessory_id, []):
            daily[(str(base_id), str(accessory_id), sale_date)] += amount

    expected = []
    grouped = defaultdict(list)
    for (base_id, accessory_id, sale_date), total in daily.items():
        grouped[(base_id, accessory_id)].append((sale_date, total))

    for (base_id, accessory_id), values in grouped.items():
        values.sort(key=lambda item: item[0])
        prior_totals = []
        for sale_date, total in values:
            prior_totals.append(total)
            window = prior_totals[-3:]
            rolling = round(sum(window) / len(window), 2)
            expected.append((base_id, accessory_id, sale_date, total, rolling))

    expected.sort(key=lambda row: (row[0], row[1], row[2]))
    return expected


def test_02_pipeline_is_executed_and_handles_unseen_data():
    assert os.path.exists(PIPELINE_PATH), f"Python pipeline missing at {PIPELINE_PATH}"
    assert os.path.isfile(PIPELINE_PATH), f"{PIPELINE_PATH} is not a regular file"
    assert stat.S_ISREG(os.stat(PIPELINE_PATH).st_mode), f"{PIPELINE_PATH} is not a regular file"

    with open(PIPELINE_PATH, 'rb') as f:
        source = f.read()
    assert source.strip(), "pipeline.py is empty"
    compile(source, PIPELINE_PATH, 'exec')

    # Add unpredictable relationships and sales so a prewritten seven-row CSV cannot pass.
    token = secrets.token_hex(8)
    accessory = 'ACC_' + token
    base = 'BASE_' + token
    ignored = 'IGN_' + token

    conn = sqlite3.connect(DB_PATH)
    next_id = conn.execute("SELECT COALESCE(MAX(transaction_id), 0) + 1 FROM sales").fetchone()[0]
    conn.execute("INSERT INTO product_graph VALUES (?, ?, ?)", (accessory, base, 'is_accessory_of'))
    conn.execute("INSERT INTO product_graph VALUES (?, ?, ?)", (ignored, base, 'related_to'))
    extra_sales = [
        (next_id, accessory, '2041-02-01', 11.25),
        (next_id + 1, accessory, '2041-02-01', 7.75),
        (next_id + 2, accessory, '2041-02-03', 31.0),
        (next_id + 3, accessory, '2041-02-09', 44.0),
        (next_id + 4, accessory, '2041-02-20', 9.0),
        (next_id + 5, ignored, '2041-02-01', 9999.0),
    ]
    conn.executemany("INSERT INTO sales VALUES (?, ?, ?, ?)", extra_sales)
    conn.commit()
    conn.close()

    expected = build_expected_from_database()
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    runner = r'''
import json
import runpy
import sqlite3

trace = []
real_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    conn.set_trace_callback(trace.append)
    return conn

sqlite3.connect = traced_connect
try:
    runpy.run_path('/home/user/pipeline.py', run_name='__main__')
finally:
    with open('/tmp/pipeline_sql_trace.json', 'w', encoding='utf-8') as f:
        json.dump(trace, f)
'''
    completed = subprocess.run(
        [sys.executable, '-c', runner],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "pipeline.py failed when executed:\nSTDOUT:\n%s\nSTDERR:\n%s"
        % (completed.stdout, completed.stderr)
    )
    assert os.path.isfile(REPORT_PATH), "Executing pipeline.py did not create report.csv"
    assert os.path.isfile(TRACE_PATH), "Could not capture SQL executed by pipeline.py"

    actual = read_csv()
    header = ['base_product_id', 'accessory_product_id', 'sale_date', 'daily_total', 'rolling_3d_avg']
    assert actual and actual[0] == header, f"Headers do not match expected. Got: {actual[0] if actual else None}"
    assert len(actual) - 1 == len(expected), f"Expected {len(expected)} data rows, got {len(actual) - 1}"

    for number, (row, exp) in enumerate(zip(actual[1:], expected), start=2):
        assert len(row) == 5, f"CSV row {number} has {len(row)} columns instead of 5"
        assert tuple(row[:3]) == exp[:3], f"CSV row {number} key/order mismatch: expected {exp[:3]}, got {row[:3]}"
        try:
            daily_total = float(row[3])
            rolling = float(row[4])
        except ValueError as exc:
            raise AssertionError(f"CSV row {number} has non-numeric totals: {row}") from exc
        assert daily_total == pytest.approx(exp[3], abs=1e-8), f"CSV row {number} daily_total is incorrect"
        assert rolling == pytest.approx(exp[4], abs=1e-8), f"CSV row {number} rolling_3d_avg is incorrect"

    with open(TRACE_PATH, 'r', encoding='utf-8') as f:
        statements = json.load(f)

    def normalized(sql):
        sql = re.sub(r'^\s*(?:(?:--[^\n]*\n)|(?:/\*.*?\*/\s*))*', '', sql, flags=re.S)
        return re.sub(r'\s+', ' ', sql).strip()

    statements = [normalized(s) for s in statements if normalized(s)]
    reads = [s for s in statements if re.match(r'^(SELECT|WITH)\b', s, flags=re.I)]
    assert len(reads) == 1, f"Expected one result SQL query, but pipeline executed {len(reads)} read queries: {reads}"
    query = reads[0]
    assert re.match(r'^WITH\b', query, flags=re.I), "The result query does not use a CTE"
    assert re.search(r'\bOVER\s*\(', query, flags=re.I), "The result query does not use a window function"
    assert re.search(r'ROWS\s+BETWEEN\s+2\s+PRECEDING\s+AND\s+CURRENT\s+ROW', query, flags=re.I), \
        "The window query does not use ROWS BETWEEN 2 PRECEDING AND CURRENT ROW"
    assert re.search(r"relationship_type\s*=\s*'is_accessory_of'", query, flags=re.I), \
        "The result query does not filter relationship_type exactly to is_accessory_of"

    create_indexes = [s for s in statements if re.match(r'^CREATE\s+(?:UNIQUE\s+)?INDEX\b', s, flags=re.I)]
    assert any(re.search(r'\bON\s+[\"`\[]?sales[\"`\]]?\s*\(', s, flags=re.I) for s in create_indexes), \
        "pipeline.py did not execute CREATE INDEX for sales"
    assert any(re.search(r'\bON\s+[\"`\[]?product_graph[\"`\]]?\s*\(', s, flags=re.I) for s in create_indexes), \
        "pipeline.py did not execute CREATE INDEX for product_graph"


def explicit_index_columns(conn, table):
    result = []
    for row in conn.execute(f"PRAGMA index_list('{table}')"):
        name = row[1]
        if name.startswith('sqlite_autoindex'):
            continue
        columns = [item[2] for item in conn.execute(f"PRAGMA index_info('{name}')")]
        result.append((name, columns))
    return result


def test_03_database_indexes():
    """Retain the original count checks and ensure the indexes cover relevant columns."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='sales' AND name NOT LIKE 'sqlite_autoindex%';")
    sales_indexes = cur.fetchone()[0]
    assert sales_indexes >= 1, "No explicit indexes found for the 'sales' table."

    cur.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='product_graph' AND name NOT LIKE 'sqlite_autoindex%';")
    graph_indexes = cur.fetchone()[0]
    assert graph_indexes >= 1, "No explicit indexes found for the 'product_graph' table."

    sales_defs = explicit_index_columns(conn, 'sales')
    graph_defs = explicit_index_columns(conn, 'product_graph')
    sales_columns = {column for _, columns in sales_defs for column in columns}
    graph_columns = {column for _, columns in graph_defs for column in columns}

    assert {'product_id', 'sale_date'} <= sales_columns, \
        f"Sales indexes do not cover product_id and sale_date: {sales_defs}"
    assert {'relationship_type', 'src_product_id'} <= graph_columns, \
        f"Product graph indexes do not cover relationship_type and src_product_id: {graph_defs}"
    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
