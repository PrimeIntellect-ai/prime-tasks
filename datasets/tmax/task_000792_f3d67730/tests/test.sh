#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
from pathlib import Path
import secrets
import sqlite3
import stat
import subprocess
import uuid
import pytest

SCRIPT_PATH = Path('/home/user/generate_catalog.py')
DB_PATH = Path('/home/user/catalog.db')
OUTPUT_PATH = Path('/home/user/catalog_output.json')


def run_generator():
    result = subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'generate_catalog.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def parse_metadata(value):
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        parsed = ast.literal_eval(value)
    assert isinstance(parsed, dict)
    return parsed


def test_00_generator_exists_is_python_and_runs():
    assert SCRIPT_PATH.exists(), f'{SCRIPT_PATH} does not exist.'
    assert stat.S_ISREG(SCRIPT_PATH.stat().st_mode), f'{SCRIPT_PATH} is not a regular file.'
    source = SCRIPT_PATH.read_text()
    compile(source, str(SCRIPT_PATH), 'exec')
    run_generator()


def test_catalog_output_exists():
    output_path = '/home/user/catalog_output.json'
    assert os.path.exists(output_path), f'Output file {output_path} does not exist. Did you run the script?'
    assert os.path.isfile(output_path), f'{output_path} is not a file.'


def test_catalog_output_content():
    output_path = '/home/user/catalog_output.json'

    try:
        with open(output_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to load JSON from {output_path}: {e}')

    assert isinstance(data, list), 'The output JSON should be a list of products.'
    assert len(data) == 2, f'Expected exactly 2 items in the output, but found {len(data)}.'

    # Check Widget A
    widget_a = next((item for item in data if item.get('id') == 1), None)
    assert widget_a is not None, 'Widget A (id=1) is missing from the output.'
    assert widget_a.get('name') == 'Widget A', 'Widget A has an incorrect name.'
    assert widget_a.get('meta') == {'weight': 10, 'color': 'red'}, 'Widget A has incorrect meta data.'

    # Check Widget B
    widget_b = next((item for item in data if item.get('id') == 2), None)
    assert widget_b is not None, 'Widget B (id=2) is missing from the output.'
    assert widget_b.get('name') == 'Widget B', 'Widget B has an incorrect name.'
    assert widget_b.get('meta') == {'weight': 15, 'color': 'blue'}, 'Widget B has incorrect meta data. Did you parse the anomalous serialization correctly?'

    # Check Widget C is NOT present
    widget_c = next((item for item in data if item.get('id') == 3), None)
    assert widget_c is None, 'Widget C (id=3, deleted) was found in output. Query result filtering failed.'


def test_generator_uses_database_and_handles_unseen_rows():
    db_backup = DB_PATH.read_bytes()
    output_existed = OUTPUT_PATH.exists()
    output_backup = OUTPUT_PATH.read_bytes() if output_existed else None

    nonce = uuid.uuid4().hex
    base_id = 1000000 + secrets.randbelow(100000000)
    normal_id = base_id
    anomalous_id = base_id + 1
    inactive_id = base_id + 2
    normal_meta = {'weight': secrets.randbelow(10000), 'token': nonce}
    anomalous_meta = {'weight': secrets.randbelow(10000), 'color': 'dynamic-' + nonce}

    try:
        with sqlite3.connect(str(DB_PATH)) as conn:
            while conn.execute(
                'SELECT 1 FROM products WHERE id IN (?, ?, ?)',
                (normal_id, anomalous_id, inactive_id),
            ).fetchone():
                normal_id += 3
                anomalous_id += 3
                inactive_id += 3

            conn.execute(
                'INSERT INTO products (id, name, metadata, status) VALUES (?, ?, ?, ?)',
                (normal_id, 'Dynamic JSON ' + nonce, json.dumps(normal_meta), 'active'),
            )
            conn.execute(
                'INSERT INTO products (id, name, metadata, status) VALUES (?, ?, ?, ?)',
                (anomalous_id, 'Dynamic repr ' + nonce, repr(anomalous_meta), 'active'),
            )
            conn.execute(
                'INSERT INTO products (id, name, metadata, status) VALUES (?, ?, ?, ?)',
                (inactive_id, 'Dynamic deleted ' + nonce, '{broken metadata', 'deleted'),
            )
            conn.commit()

            active_rows = conn.execute(
                "SELECT id, name, metadata FROM products WHERE status = 'active'"
            ).fetchall()

        expected = {
            row_id: {'id': row_id, 'name': name, 'meta': parse_metadata(metadata)}
            for row_id, name, metadata in active_rows
        }

        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        run_generator()

        assert OUTPUT_PATH.is_file(), 'The generator did not create catalog_output.json.'
        with OUTPUT_PATH.open() as f:
            actual = json.load(f)

        assert isinstance(actual, list), 'The generated catalog must be a list.'
        assert all(isinstance(item, dict) for item in actual), 'Every catalog item must be an object.'
        assert all(isinstance(item.get('meta'), dict) for item in actual), 'Every meta field must be a parsed object.'

        actual_by_id = {item.get('id'): item for item in actual}
        assert len(actual_by_id) == len(actual), 'The generated catalog contains duplicate or missing IDs.'
        assert set(actual_by_id) == set(expected), 'The output IDs do not exactly match active database products.'
        for row_id, expected_item in expected.items():
            assert actual_by_id[row_id].get('name') == expected_item['name']
            assert actual_by_id[row_id].get('meta') == expected_item['meta']
        assert inactive_id not in actual_by_id, 'A deleted product was included in the output.'
    finally:
        DB_PATH.write_bytes(db_backup)
        if output_existed:
            OUTPUT_PATH.write_bytes(output_backup)
        elif OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
