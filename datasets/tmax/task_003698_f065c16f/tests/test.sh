#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_pipeline.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import unicodedata
import uuid
from pathlib import Path

import pandas as pd

PIPELINE = Path('/home/user/pipeline.py')
CATALOG = Path('/home/user/inputs/catalog.json')
INVENTORY = Path('/home/user/inputs/inventory.csv')
OUTPUT_DIR = Path('/home/user/outputs')
LOG = OUTPUT_DIR / 'pipeline.log'
PARQUET = OUTPUT_DIR / 'final_catalog.parquet'
EXPECTED_STEPS = [
    'Step extract completed',
    'Step clean completed',
    'Step extract_features completed',
    'Step load completed',
]


def clean_outputs():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in (LOG, PARQUET):
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists() or path.is_symlink():
            path.unlink()


def run_pipeline():
    clean_outputs()
    result = subprocess.run(
        ['python3', str(PIPELINE)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'pipeline.py exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def check_log():
    assert LOG.is_file(), f'The log file {LOG} does not exist.'
    content = LOG.read_text(encoding='utf-8')
    for step in EXPECTED_STEPS:
        assert step in content, f"Expected log entry '{step}' not found in {LOG}."

    lines = [line.strip() for line in content.splitlines()]
    positions = []
    for step in EXPECTED_STEPS:
        assert step in lines, f"Expected exact log line '{step}' not found in {LOG}."
        positions.append(lines.index(step))
    assert positions == sorted(positions), 'Pipeline steps were not logged in the required order.'


def read_output():
    assert PARQUET.is_file(), f'The final output file {PARQUET} does not exist.'
    try:
        return pd.read_parquet(PARQUET)
    except Exception as exc:
        raise AssertionError(f'Failed to read {PARQUET} as a Parquet file: {exc}') from exc


def normalized(value):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFKC', value).strip())


def category(value):
    lowered = value.casefold()
    if any(term.casefold() in lowered for term in ('shoe', 'zapato', '靴')):
        return 'Footwear'
    if any(term.casefold() in lowered for term in ('shirt', 'camiseta', 'シャツ')):
        return 'Apparel'
    return 'Other'


def check_generated_case():
    suffix = uuid.uuid4().hex
    ids = {name: f'{name}-{suffix}' for name in ('A', 'B', 'C', 'D', 'E', 'INV')}
    descriptions = {
        ids['A']: f'  Ｒｕｎｎｉｎｇ\t shoes　{suffix}  ',
        ids['B']: f'Camiseta   de algodo\u0301n　{suffix}',
        ids['C']: f'革　靴  {suffix}',
        ids['D']: f'  Televisor\n 8K   {suffix}  ',
        ids['E']: f'Shirt without inventory {suffix}',
    }
    catalog_rows = [
        {'id': ids['A'], 'desc': descriptions[ids['A']]},
        {'id': ids['A'], 'desc': f'duplicate must not win {suffix}'},
        {'id': ids['B'], 'desc': descriptions[ids['B']]},
        {'id': ids['C'], 'desc': descriptions[ids['C']]},
        {'id': ids['D'], 'desc': descriptions[ids['D']]},
        {'id': ids['E'], 'desc': descriptions[ids['E']]},
    ]

    joined_ids = [ids['A'], ids['B'], ids['C'], ids['D']]
    inventory_values = {}
    csv_lines = ['id,price,stock']
    for index, item_id in enumerate(joined_ids):
        cents = 1000 + secrets.randbelow(90000) + index
        price_text = f'{cents / 100:.2f}'
        stock = 1 + secrets.randbelow(900) + index
        inventory_values[item_id] = (float(price_text), stock)
        csv_lines.append(f'{item_id},{price_text},{stock}')
    csv_lines.append(f"{ids['INV']},7.77,3")

    CATALOG.write_text(json.dumps(catalog_rows, ensure_ascii=False), encoding='utf-8')
    INVENTORY.write_text('\n'.join(csv_lines) + '\n', encoding='utf-8')
    run_pipeline()
    check_log()
    df = read_output()

    assert len(df) == 4, f'Expected 4 dynamically joined rows, got {len(df)}.'
    expected_columns = {'id', 'desc', 'category', 'price', 'stock'}
    assert set(df.columns) == expected_columns, (
        f'Expected columns {expected_columns}, got {set(df.columns)}.'
    )
    assert set(df['id']) == set(joined_ids), f'Incorrect inner-join IDs: {set(df["id"])}'

    for item_id in joined_ids:
        rows = df[df['id'] == item_id]
        assert len(rows) == 1, f'Expected exactly one row for generated ID {item_id}.'
        row = rows.iloc[0]
        expected_desc = normalized(descriptions[item_id])
        expected_price, expected_stock = inventory_values[item_id]
        assert row['desc'] == expected_desc, f'Incorrect description for {item_id}: {row["desc"]}'
        assert row['category'] == category(expected_desc), (
            f'Incorrect category for {item_id}: {row["category"]}'
        )
        assert float(row['price']) == expected_price, f'Incorrect price for {item_id}: {row["price"]}'
        assert int(row['stock']) == expected_stock, f'Incorrect stock for {item_id}: {row["stock"]}'


def write_original_fixture():
    rows = [
        {'id': 'P001', 'desc': 'Ｒｕｎｎｉｎｇ shoes (黒) '},
        {'id': 'P001', 'desc': 'Running shoes (black) - duplicate'},
        {'id': 'P002', 'desc': 'Camiseta de algodo\u0301n　XL'},
        {'id': 'P003', 'desc': 'Televisor 4K 55"'},
        {'id': 'P005', 'desc': '   Classic    シャツ  '},
    ]
    CATALOG.write_text(json.dumps(rows, ensure_ascii=False), encoding='utf-8')
    INVENTORY.write_text(
        'id,price,stock\n'
        'P001,89.99,120\n'
        'P002,19.99,50\n'
        'P003,450.00,10\n'
        'P004,10.00,0\n'
        'P005,25.00,200\n',
        encoding='utf-8',
    )


def check_original_case():
    write_original_fixture()
    run_pipeline()
    check_log()
    df = read_output()

    assert len(df) == 4, f'Expected 4 rows in the final dataset, got {len(df)}.'
    expected_columns = {'id', 'desc', 'category', 'price', 'stock'}
    assert set(df.columns) == expected_columns, f'Expected columns {expected_columns}, got {set(df.columns)}.'

    expected = {
        'P001': ('Running shoes (黒)', 'Footwear', 89.99, 120),
        'P002': ('Camiseta de algodón XL', 'Apparel', 19.99, 50),
        'P003': ('Televisor 4K 55"', 'Other', 450.00, 10),
        'P005': ('Classic シャツ', 'Apparel', 25.00, 200),
    }
    for item_id, (desc, cat, price, stock) in expected.items():
        rows = df[df['id'] == item_id]
        assert len(rows) == 1, f'Expected exactly one row for {item_id}.'
        row = rows.iloc[0]
        assert row['desc'] == desc, f'Incorrect normalized description for {item_id}: {row["desc"]}'
        assert row['category'] == cat, f'Incorrect category for {item_id}: {row["category"]}'
        assert float(row['price']) == price, f'Incorrect price for {item_id}: {row["price"]}'
        assert int(row['stock']) == stock, f'Incorrect stock for {item_id}: {row["stock"]}'


def main():
    assert PIPELINE.exists(), f'The required script {PIPELINE} does not exist.'
    assert stat.S_ISREG(os.lstat(PIPELINE).st_mode), f'{PIPELINE} is not a regular file.'
    assert PIPELINE.stat().st_size > 0, f'{PIPELINE} is empty.'

    original_catalog = CATALOG.read_bytes()
    original_inventory = INVENTORY.read_bytes()
    try:
        check_generated_case()
        check_original_case()
    finally:
        CATALOG.write_bytes(original_catalog)
        INVENTORY.write_bytes(original_inventory)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
