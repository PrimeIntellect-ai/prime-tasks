#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import secrets
import subprocess
import pytest

SOURCE = '/home/user/process.go'
BINARY = '/tmp/process_submission'
OUTPUT = '/home/user/output.json'
INPUTS = [
    '/home/user/users.csv',
    '/home/user/friends.csv',
    '/home/user/transactions.csv',
]

def get_expected_output():
    """Derive the expected output directly from the input CSV files."""
    users = {}
    with open('/home/user/users.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[int(row['user_id'])] = row['name']

    out_degrees = {u: 0 for u in users}
    with open('/home/user/friends.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src = int(row['source_id'])
            out_degrees[src] = out_degrees.get(src, 0) + 1

    max_amounts = {u: 0.0 for u in users}
    with open('/home/user/transactions.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = int(row['user_id'])
            amt = float(row['amount'])
            if amt > max_amounts.get(uid, 0.0):
                max_amounts[uid] = amt

    results = []
    for uid, name in users.items():
        max_amt = max_amounts[uid]
        if max_amt > 50.0:
            results.append({
                "user_id": uid,
                "name": name,
                "out_degree": out_degrees[uid],
                "max_amount": max_amt
            })

    results.sort(key=lambda x: (-x['max_amount'], -x['out_degree'], x['user_id']))
    return results[2:4]

def assert_output_matches_expected():
    with open(OUTPUT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('/home/user/output.json is not valid JSON')

    expected = get_expected_output()
    assert isinstance(data, list), 'Output JSON must be an array (list)'
    assert len(data) == len(expected), f'Expected {len(expected)} items in the paginated output, but got {len(data)}'

    for i, (act, exp) in enumerate(zip(data, expected)):
        assert act.get('user_id') == exp['user_id'], f"Item {i}: expected user_id {exp['user_id']}, got {act.get('user_id')}"
        assert act.get('name') == exp['name'], f"Item {i}: expected name '{exp['name']}', got '{act.get('name')}'"
        assert act.get('out_degree') == exp['out_degree'], f"Item {i}: expected out_degree {exp['out_degree']}, got {act.get('out_degree')}"
        act_amount = act.get('max_amount')
        assert act_amount is not None, f"Item {i}: missing 'max_amount'"
        assert float(act_amount) == exp['max_amount'], f"Item {i}: expected max_amount {exp['max_amount']}, got {act_amount}"

@pytest.fixture(scope='session', autouse=True)
def compile_and_run_submission():
    assert os.path.exists(SOURCE), '/home/user/process.go does not exist. Did you write the Go program?'
    subprocess.run(
        ['go', 'build', '-o', BINARY, SOURCE],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([BINARY], check=True, timeout=15, cwd='/home/user')

def test_go_file_exists():
    assert os.path.exists('/home/user/process.go'), '/home/user/process.go does not exist. Did you write the Go program?'

def test_output_json_exists():
    assert os.path.exists('/home/user/output.json'), '/home/user/output.json does not exist. Did you compile and run the program?'

def test_output_json_content():
    assert_output_matches_expected()

def test_program_processes_changed_inputs():
    backups = {path: open(path, 'rb').read() for path in INPUTS}
    output_backup = open(OUTPUT, 'rb').read() if os.path.exists(OUTPUT) else None

    offset = 10000 + secrets.randbelow(800000)
    ids = [offset + n for n in (11, 22, 33, 44, 55, 66, 77)]
    a, b, c, d, e, f, g = ids
    token = secrets.token_hex(5)
    jitter = secrets.randbelow(40) / 10.0

    try:
        with open('/home/user/users.csv', 'w', newline='') as fh:
            writer = csv.writer(fh)
            writer.writerow(['user_id', 'name'])
            for i, uid in enumerate(ids):
                writer.writerow([uid, f'changed-{token}-{i}'])

        with open('/home/user/friends.csv', 'w', newline='') as fh:
            writer = csv.writer(fh)
            writer.writerow(['source_id', 'target_id'])
            writer.writerows([
                [b, a],
                [c, a],
                [d, a], [d, b], [d, c],
                [e, a], [e, b],
                [g, a], [g, b], [g, c], [g, d],
            ])

        with open('/home/user/transactions.csv', 'w', newline='') as fh:
            writer = csv.writer(fh)
            writer.writerow(['tx_id', 'user_id', 'amount', 'timestamp'])
            amounts = [
                ('a-old', a, 12.5), ('a-max', a, 500.0 + jitter),
                ('b-max', b, 400.0 + jitter),
                ('c-max', c, 300.0 + jitter),
                ('d-old', d, 75.0), ('d-max', d, 300.0 + jitter),
                ('e-max', e, 200.0 + jitter),
                ('f-max', f, 100.0 + jitter),
                ('g-threshold', g, 50.0),
            ]
            for txid, uid, amount in amounts:
                writer.writerow([txid, uid, amount, '2026-01-01T00:00:00Z'])

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        subprocess.run([BINARY], check=True, timeout=15, cwd='/home/user')
        assert os.path.exists(OUTPUT), 'Program did not generate output.json for changed inputs'
        assert_output_matches_expected()
    finally:
        for path, content in backups.items():
            with open(path, 'wb') as fh:
                fh.write(content)
        if output_backup is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, 'wb') as fh:
                fh.write(output_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
