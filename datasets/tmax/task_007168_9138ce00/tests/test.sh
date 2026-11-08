#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import shlex
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/etl.py')
USERS = Path('/home/user/data/users.csv')
TRANSACTIONS = Path('/home/user/data/transactions.json')
OUTPUT = Path('/home/user/output/anomalies.jsonl')
EXPECTED_KEYS = {'tx_id', 'user_id', 'masked_ssn', 'masked_email', 'amount', 'tokens'}


def read_jsonl(path):
    records = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Line in {path} is not valid JSON: {line}")
    return records


def test_anomalies_file_exists():
    assert os.path.isfile('/home/user/output/anomalies.jsonl'), "Output file /home/user/output/anomalies.jsonl does not exist."


def test_anomalies_content():
    file_path = '/home/user/output/anomalies.jsonl'
    anomalies = read_jsonl(file_path)

    assert len(anomalies) == 2, f"Expected exactly 2 anomalous records, found {len(anomalies)}."

    tx4 = next((a for a in anomalies if a.get('tx_id') == 'tx4'), None)
    assert tx4 is not None, "Expected anomaly 'tx4' is missing from the output."
    assert tx4.get('user_id') == 1, "tx4 user_id is incorrect."
    assert tx4.get('masked_ssn') == 'XXX-XX-3333', "tx4 masked_ssn is incorrect."
    assert tx4.get('masked_email') == 'a***@example.com', "tx4 masked_email is incorrect."
    assert tx4.get('amount') == 5000, "tx4 amount is incorrect."
    assert tx4.get('tokens') == ['luxury', 'watch', 'purchase'], "tx4 tokens are incorrect."

    forbidden_keys = {'ssn', 'email', 'description'}
    assert not forbidden_keys.intersection(tx4.keys()), "Output JSON objects must not contain original ssn, email, or description."
    assert set(tx4) == EXPECTED_KEYS, "Output JSON objects must contain exactly the required keys."

    tx8 = next((a for a in anomalies if a.get('tx_id') == 'tx8'), None)
    assert tx8 is not None, "Expected anomaly 'tx8' is missing from the output."
    assert tx8.get('user_id') == 2, "tx8 user_id is incorrect."
    assert tx8.get('masked_ssn') == 'XXX-XX-6666', "tx8 masked_ssn is incorrect."
    assert tx8.get('masked_email') == 'b***@test.org', "tx8 masked_email is incorrect."
    assert tx8.get('amount') == 200, "tx8 amount is incorrect."
    assert tx8.get('tokens') == ['fancy', 'dinner', 'at', '8pm'], "tx8 tokens are incorrect."
    assert not forbidden_keys.intersection(tx8.keys()), "Output JSON objects must not contain original ssn, email, or description."
    assert set(tx8) == EXPECTED_KEYS, "Output JSON objects must contain exactly the required keys."


def reference_result(users, transactions):
    users_by_id = {int(u['user_id']): u for u in users}
    amounts = defaultdict(list)
    for tx in transactions:
        amounts[int(tx['user_id'])].append(tx['amount'])

    result = []
    for tx in transactions:
        uid = int(tx['user_id'])
        vals = amounts[uid]
        mean = sum(vals) / len(vals)
        std = math.sqrt(sum((value - mean) ** 2 for value in vals) / len(vals))
        if tx['amount'] > mean + 1.5 * std:
            user = users_by_id[uid]
            local, domain = user['email'].split('@', 1)
            ssn = user['ssn']
            normalized = ''.join(ch.lower() for ch in tx['description'] if ch.isalnum() or ch == ' ')
            result.append({
                'tx_id': tx['tx_id'],
                'user_id': uid,
                'masked_ssn': 'XXX-XX-' + ssn[-4:],
                'masked_email': local[0] + '***@' + domain,
                'amount': tx['amount'],
                'tokens': normalized.split(),
            })
    return result


def test_script_exists_and_processes_changed_inputs():
    assert SCRIPT.is_file(), "/home/user/etl.py does not exist or is not a regular file."

    nonce = secrets.token_hex(5)
    uid1 = secrets.randbelow(700000) + 100000
    uid2 = uid1 + 1
    base = secrets.randbelow(40) + 10
    users = [
        {'user_id': str(uid1), 'name': 'Dynamic One', 'email': f'zeta.{nonce}@dynamic.example', 'ssn': '321-54-9876'},
        {'user_id': str(uid2), 'name': 'Dynamic Two', 'email': f'q{nonce}@other.test', 'ssn': '765-43-2109'},
    ]
    transactions = []
    descriptions = ['ordinary item', 'Second-item!', 'THIRD, ITEM?', 'MIXED.Case!!! item_42 paid$ now']
    for index, amount in enumerate([base, base + 1, base + 2, base + 1000]):
        transactions.append({
            'tx_id': f'{nonce}-a{index}', 'user_id': uid1, 'amount': amount,
            'timestamp': f'2025-02-0{index + 1}T10:00:00Z', 'description': descriptions[index],
        })
    for index, amount in enumerate([25, 25, 25, 25]):
        transactions.append({
            'tx_id': f'{nonce}-b{index}', 'user_id': uid2, 'amount': amount,
            'timestamp': f'2025-03-0{index + 1}T10:00:00Z', 'description': 'Not anomalous.',
        })

    expected = reference_result(users, transactions)
    saved_users = USERS.read_bytes()
    saved_transactions = TRANSACTIONS.read_bytes()
    saved_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        with USERS.open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['user_id', 'name', 'email', 'ssn'])
            writer.writeheader()
            writer.writerows(users)
        TRANSACTIONS.write_text(json.dumps(transactions))
        if OUTPUT.exists():
            OUTPUT.unlink()

        proc = subprocess.run(
            ['runuser', '-u', 'user', '--', 'python3', str(SCRIPT)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, f"etl.py failed on changed inputs:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        assert OUTPUT.is_file(), "etl.py did not create /home/user/output/anomalies.jsonl."
        actual = read_jsonl(OUTPUT)
        assert all(set(record) == EXPECTED_KEYS for record in actual), "Dynamic output objects do not contain exactly the required keys."
        assert sorted(actual, key=lambda x: x['tx_id']) == sorted(expected, key=lambda x: x['tx_id']), "etl.py produced incorrect output for changed inputs."
    finally:
        USERS.write_bytes(saved_users)
        TRANSACTIONS.write_bytes(saved_transactions)
        if saved_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(saved_output)


def active_cron_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]


def is_real_etl_job(line):
    match = re.match(r'^(?:\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+(.+)$', line)
    if not match:
        return False
    command = match.group(1).split('#', 1)[0].strip()
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    if not words:
        return False
    if words[0] == '/home/user/etl.py':
        return True
    return os.path.basename(words[0]) in {'python', 'python3'} and len(words) >= 2 and words[1] == '/home/user/etl.py'


def test_cron_configuration():
    assert os.path.isfile('/home/user/crontab.bak'), "/home/user/crontab.bak backup file is missing."

    try:
        crontab_out = subprocess.check_output(['crontab', '-u', 'user', '-l'], stderr=subprocess.STDOUT).decode()
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for 'user'. Ensure the crontab was installed correctly.")

    has_schedule = '*/15 * * * *' in crontab_out or '0,15,30,45 * * * *' in crontab_out
    has_script = 'etl.py' in crontab_out
    assert has_schedule, "Crontab does not contain the correct schedule (every 15 minutes)."
    assert has_script, "Crontab does not contain a reference to 'etl.py'."

    installed_lines = active_cron_lines(crontab_out)
    real_jobs = [line for line in installed_lines if is_real_etl_job(line)]
    assert real_jobs, "Crontab lacks an active every-15-minutes job that actually invokes /home/user/etl.py."

    backup_text = Path('/home/user/crontab.bak').read_text()
    backup_lines = active_cron_lines(backup_text)
    assert any(line in backup_lines for line in real_jobs), "crontab.bak does not contain the installed ETL cron job."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
