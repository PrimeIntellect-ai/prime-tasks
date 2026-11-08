#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import random
import shutil
import string
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/etl.py')
CRM_DIR = Path('/home/user/data/crm')
TX_DIR = Path('/home/user/data/transactions')
OUTPUT = Path('/home/user/output/joined_data.csv')
HEADER = ['tx_id', 'crm_name', 'tx_name', 'masked_email', 'masked_cc']


def run_etl():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'ETL script failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert OUTPUT.is_file(), f'Output CSV missing at {OUTPUT}'
    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        return list(csv.reader(f))


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def mask_email(email):
    local, domain = email.split('@', 1)
    return local[0] + '***@' + domain


def mask_cc(cc):
    cc = str(cc)
    return '*' * max(0, len(cc) - 4) + cc[-4:]


def random_word(length=8):
    return ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(length)).capitalize()


def mutate(word, count):
    chars = list(word)
    for index in range(count):
        original = chars[index]
        chars[index] = 'Z' if original != 'Z' else 'Y'
    return ''.join(chars)


def assert_real_multiprocessing_usage(content):
    tree = ast.parse(content, filename=str(SCRIPT))
    module_aliases = set()
    pool_names = set()
    process_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing':
                    module_aliases.add(alias.asname or 'multiprocessing')
        elif isinstance(node, ast.ImportFrom) and node.module == 'multiprocessing':
            for alias in node.names:
                if alias.name == 'Pool':
                    pool_names.add(alias.asname or alias.name)
                elif alias.name == 'Process':
                    process_names.add(alias.asname or alias.name)

    assert module_aliases or pool_names or process_names, 'The script must import multiprocessing.'

    def rooted_in_module(node):
        if isinstance(node, ast.Name):
            return node.id in module_aliases
        if isinstance(node, ast.Attribute):
            return rooted_in_module(node.value)
        if isinstance(node, ast.Call):
            return rooted_in_module(node.func)
        return False

    has_pool = False
    has_process = False
    has_pool_map = False
    has_process_start = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            has_pool |= func.id in pool_names
            has_process |= func.id in process_names
        elif isinstance(func, ast.Attribute):
            if func.attr == 'Pool' and rooted_in_module(func.value):
                has_pool = True
            if func.attr == 'Process' and rooted_in_module(func.value):
                has_process = True
            if func.attr in {'map', 'starmap', 'imap', 'imap_unordered', 'map_async', 'starmap_async'}:
                has_pool_map = True
            if func.attr == 'start':
                has_process_start = True

    assert (has_pool and has_pool_map) or (has_process and has_process_start), (
        'The script must actually use multiprocessing Pool mapping or start multiprocessing Process workers.'
    )


def test_etl_end_to_end_and_randomized_inputs():
    # Preserve the original source assertion and strengthen it beyond a comment substring.
    assert SCRIPT.is_file(), f'ETL script missing at {SCRIPT}'
    content = SCRIPT.read_text(encoding='utf-8')
    assert 'multiprocessing' in content, "The script does not seem to use the 'multiprocessing' module as required."
    assert_real_multiprocessing_usage(content)

    # Execute the submitted artifact on the original fixture before checking its exact output.
    actual_rows = run_etl()
    expected_rows = [
        HEADER,
        ['TX101', 'Jonathon Doe', 'Jonathan Doe', 'j***@gmail.com', '************4444'],
        ['TX102', 'Alice Smith', 'Alice Smyth', 'a***@yahoo.com', '************8888'],
    ]
    assert len(actual_rows) > 0, 'The output CSV is empty.'
    assert actual_rows[0] == expected_rows[0], f'Expected header {expected_rows[0]}, but got {actual_rows[0]}'
    assert actual_rows == expected_rows, f'Expected CSV contents {expected_rows}, but got {actual_rows}'

    # Replace the fixed fixture with unpredictable records and execute the script again.
    shutil.rmtree(CRM_DIR)
    shutil.rmtree(TX_DIR)
    CRM_DIR.mkdir(parents=True)
    TX_DIR.mkdir(parents=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    first1, first2, first3, first4 = [random_word() for _ in range(4)]
    crm_records = [
        {'name': f'{first1} Alder', 'email': f'{first1.lower()}.one@alpha.example'},
        {'name': f'{first2} Birch', 'email': f'{first2.lower()}_two@beta.example'},
        {'name': f'{first3} Cedar', 'email': f'{first3.lower()}3@gamma.example'},
        {'name': f'{first4} Dorian', 'email': f'{first4.lower()}.four@delta.example'},
    ]

    tx_records = [
        {'tx_id': 'TX9' + random_word(5).upper(), 'name': f'{mutate(first1, 1)} Alder', 'cc': '410012341234' + ''.join(random.SystemRandom().choice(string.digits) for _ in range(4))},
        {'tx_id': 'TX2' + random_word(5).upper(), 'name': f'{mutate(first2, 2)} Birch', 'cc': '520056785678' + ''.join(random.SystemRandom().choice(string.digits) for _ in range(4))},
        {'tx_id': 'TX5' + random_word(5).upper(), 'name': f'{mutate(first3, 3)} Cedar', 'cc': '630090129012' + ''.join(random.SystemRandom().choice(string.digits) for _ in range(4))},
        {'tx_id': 'TX1' + random_word(5).upper(), 'name': f'{random_word()} Zephyr', 'cc': '740034563456' + ''.join(random.SystemRandom().choice(string.digits) for _ in range(4))},
    ]

    log_templates = [
        'Case note: Customer {name} called about an order. Contact: {email}.\n',
        'Case note: Customer {name} sent a billing request from {email}.\n',
        'Case note: Customer {name} called for assistance; reply to {email}.\n',
        'Case note: Customer {name} sent an update using {email}.\n',
    ]
    for i, record in enumerate(crm_records):
        (CRM_DIR / f'random_{i}.txt').write_text(log_templates[i].format(**record), encoding='utf-8')

    # Exercise both multiple JSON files and multiple records in one JSON array.
    (TX_DIR / 'batch_b.json').write_text(json.dumps([tx_records[0], tx_records[3]]), encoding='utf-8')
    (TX_DIR / 'batch_a.json').write_text(json.dumps([tx_records[2], tx_records[1]]), encoding='utf-8')

    expected_dynamic = []
    for crm in crm_records:
        for tx in tx_records:
            if levenshtein(crm['name'], tx['name']) <= 2:
                expected_dynamic.append([
                    tx['tx_id'],
                    crm['name'],
                    tx['name'],
                    mask_email(crm['email']),
                    mask_cc(tx['cc']),
                ])
    expected_dynamic.sort(key=lambda row: row[0])

    dynamic_rows = run_etl()
    assert dynamic_rows, 'The randomized output CSV is empty.'
    assert dynamic_rows[0] == HEADER, f'Expected exact header {HEADER}, got {dynamic_rows[0]}'
    assert dynamic_rows[1:] == expected_dynamic, (
        f'Randomized extraction, distance join, masking, or tx_id sorting is incorrect. '
        f'Expected {expected_dynamic}, got {dynamic_rows[1:]}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
