#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
USERS = HOME / 'users.jsonl'
TRANSACTIONS = HOME / 'transactions.jsonl'
OUTPUT = HOME / 'final_output.jsonl'


@pytest.fixture(scope='session', autouse=True)
def restore_files():
    paths = [USERS, TRANSACTIONS, OUTPUT]
    saved = {p: p.read_bytes() if p.exists() else None for p in paths}
    yield
    for path, content in saved.items():
        if content is None:
            path.unlink(missing_ok=True)
        else:
            path.write_bytes(content)


def read_output():
    assert OUTPUT.is_file(), f'Expected output file not found at {OUTPUT}.'
    lines = OUTPUT.read_text(encoding='utf-8').splitlines()
    assert lines, 'Output file is empty.'
    assert all(line.strip() for line in lines), 'Output contains a blank line.'
    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as exc:
            pytest.fail(f'Line {i + 1} is not valid JSON: {exc}')
    return records


def test_01_original_output_assertions():
    records = read_output()
    assert len(records) == 4, f'Expected 4 lines in {OUTPUT}, found {len(records)}.'

    tx_ids = [r.get('tx_id') for r in records]
    assert tx_ids == ['t1', 't2', 't3', 't4'], \
        f'Records are not sorted by tx_id ascending. Found: {tx_ids}'

    expected_names = {
        1: 'Alice Böhm',
        2: 'Bob Sm[?]th',
        3: 'Charlie [?]'
    }

    for r in records:
        tx_id = r.get('tx_id')
        user_id = r.get('user_id')
        for field in ['tx_id', 'user_id', 'amount', 'tx_coords', 'name',
                      'email', 'home_coords', 'flagged']:
            assert field in r, f"Record {tx_id} is missing required field '{field}'."

        assert r['email'] == '***@***.***', \
            f"Email for {tx_id} is not properly masked. Found: {r['email']}"
        expected_name = expected_names.get(user_id)
        assert r['name'] == expected_name, \
            f"Name for {tx_id} (user {user_id}) is incorrect. Expected '{expected_name}', found '{r['name']}'."

        x1, y1 = r['home_coords']
        x2, y2 = r['tx_coords']
        dist = math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
        expected_flag = dist > 10.0
        assert r['flagged'] is expected_flag, \
            f"Flagged status for {tx_id} is incorrect. Dist: {dist}, Expected: {expected_flag}, Found: {r['flagged']}"


def find_python_scripts():
    scripts = []
    for path in HOME.rglob('*'):
        if not path.is_file():
            continue
        try:
            first = path.open('rb').readline(256).decode('utf-8', 'ignore').lower()
        except OSError:
            continue
        if path.suffix == '.py' or (first.startswith('#!') and 'python' in first):
            scripts.append(path)
    assert scripts, 'No Python pipeline script was found under /home/user.'
    return sorted(scripts)


def assert_multiprocessing_used(scripts):
    imported = False
    worker_construct = False
    for path in scripts:
        try:
            tree = ast.parse(path.read_text(encoding='utf-8'))
        except (OSError, UnicodeDecodeError, SyntaxError):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported |= any(alias.name == 'multiprocessing' or
                                alias.name.startswith('multiprocessing.')
                                for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                imported |= bool(node.module and
                                 (node.module == 'multiprocessing' or
                                  node.module.startswith('multiprocessing.')))
            elif isinstance(node, ast.Call):
                func = node.func
                if isinstance(func, ast.Name) and func.id in {'Pool', 'Process'}:
                    worker_construct = True
                elif isinstance(func, ast.Attribute) and func.attr in {'Pool', 'Process'}:
                    worker_construct = True
    assert imported, 'The submitted Python pipeline does not import multiprocessing.'
    assert worker_construct, 'The submitted pipeline does not create a multiprocessing Pool or Process.'


def clean_user_line(line):
    pattern = re.compile(r'\\u(.{4})')

    def replace_invalid(match):
        chars = match.group(1)
        if all(c in '0123456789abcdefABCDEF' for c in chars):
            return match.group(0)
        return '[?]'

    return json.loads(pattern.sub(replace_invalid, line))


def derive_expected():
    users = {}
    for line in USERS.read_text(encoding='utf-8').splitlines():
        if line.strip():
            user = clean_user_line(line)
            users[user['id']] = user

    transactions = [json.loads(line) for line in
                    TRANSACTIONS.read_text(encoding='utf-8').splitlines()
                    if line.strip()]
    expected = []
    for tx in transactions:
        user = users[tx['user_id']]
        x1, y1 = user['home_coords']
        x2, y2 = tx['tx_coords']
        merged = dict(tx)
        merged['name'] = user['name']
        merged['email'] = '***@***.***'
        merged['home_coords'] = user['home_coords']
        merged['flagged'] = math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2) > 10.0
        expected.append(merged)
    return sorted(expected, key=lambda r: r['tx_id'])


def validate_dynamic_output(expected):
    actual = read_output()
    assert len(actual) == len(expected), \
        f'Expected {len(expected)} joined records, found {len(actual)}.'
    assert [r.get('tx_id') for r in actual] == [r['tx_id'] for r in expected], \
        'Dynamic output is not sorted by tx_id or does not contain the input transactions.'

    for got, want in zip(actual, expected):
        tx_id = want['tx_id']
        for field, value in want.items():
            assert field in got, f"Record {tx_id} is missing required field '{field}'."
            if field == 'flagged':
                assert type(got[field]) is bool, f'flagged for {tx_id} must be a JSON boolean.'
            assert got[field] == value, \
                f"Incorrect field '{field}' for {tx_id}: expected {value!r}, found {got[field]!r}."


def write_dynamic_inputs():
    token = secrets.token_hex(6)
    base = secrets.randbelow(50000) + 1000
    users = [
        f'{{"id": {base + 7}, "name": "Ren\\u00e9 {token}", "email": "one-{token}@example.test", "home_coords": [1.25, -3.5]}}',
        f'{{"id": {base + 19}, "name": "Mira Q\\u0Z9Qtail {token}", "email": "two-{token}@example.test", "home_coords": [-20.0, 8.75]}}',
        f'{{"id": {base + 31}, "name": "N\\u12XY {token}", "email": "three-{token}@example.test", "home_coords": [100.5, 200.25]}}',
        f'{{"id": {base + 43}, "name": "Plain {token}", "email": "four-{token}@example.test", "home_coords": [0.0, 0.0]}}'
    ]
    txs = [
        {'tx_id': f'z-{token}-2', 'user_id': base + 7, 'amount': 913.27,
         'tx_coords': [1.25, 6.5], 'memo': f'edge-{token}'},
        {'tx_id': f'a-{token}-9', 'user_id': base + 19, 'amount': -4.125,
         'tx_coords': [-2.0, 8.75], 'memo': f'far-{token}'},
        {'tx_id': f'm-{token}-1', 'user_id': base + 31, 'amount': 0.01,
         'tx_coords': [100.6, 200.35], 'memo': f'near-{token}'},
        {'tx_id': f'b-{token}-7', 'user_id': base + 43, 'amount': 777.0,
         'tx_coords': [6.0, 8.0], 'memo': f'ten-{token}'},
        {'tx_id': f'y-{token}-3', 'user_id': base + 7, 'amount': 42.42,
         'tx_coords': [30.0, -40.0], 'memo': f'repeat-{token}'}
    ]
    USERS.write_text('\n'.join(users) + '\n', encoding='utf-8')
    TRANSACTIONS.write_text(
        ''.join(json.dumps(tx, ensure_ascii=False) + '\n' for tx in txs),
        encoding='utf-8'
    )


def test_02_pipeline_executes_on_unseen_inputs():
    scripts = find_python_scripts()
    assert_multiprocessing_used(scripts)
    write_dynamic_inputs()
    expected = derive_expected()

    errors = []
    for script in scripts:
        # Restore the unseen inputs before every possible entry point.
        users_data = USERS.read_bytes()
        tx_data = TRANSACTIONS.read_bytes()
        OUTPUT.unlink(missing_ok=True)
        USERS.write_bytes(users_data)
        TRANSACTIONS.write_bytes(tx_data)
        try:
            result = subprocess.run(
                ['runuser', '-u', 'user', '--', 'python3', str(script)],
                cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=20
            )
        except subprocess.TimeoutExpired:
            errors.append(f'{script}: timed out')
            continue
        if result.returncode != 0:
            errors.append(f'{script}: exited {result.returncode}: {result.stderr[-300:]}')
            continue
        try:
            validate_dynamic_output(expected)
            return
        except AssertionError as exc:
            errors.append(f'{script}: {exc}')

    pytest.fail('No submitted Python script produced correct output for unseen input. ' +
                ' | '.join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
