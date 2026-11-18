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
from pathlib import Path

import pytest

PROJECT = Path('/home/user/audit_tool')
DATA_DIR = Path('/home/user/audit_data')
OUTPUT = Path('/home/user/flagged_employees.json')


def run_as_user(args, timeout=180):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user', *args],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(args)}\n{result.stdout}"


def write_original_fixture():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / 'departments.csv').write_text(
        'dept_code,dept_name\nD1,Retail\nD2,Investment\nD3,Legal\nD4,HR\n'
    )
    (DATA_DIR / 'users.csv').write_text(
        'uid,name,dept_code\n'
        '1,Alice,D2\n2,Bob,D2\n3,Charlie,D1\n4,Diana,D2\n5,Eve,D3\n6,Frank,D2\n'
    )
    (DATA_DIR / 'comms.log').write_text(
        '1700000000,1,2\n1700000001,3,2\n1700000002,4,2\n'
        '1700000003,5,2\n1700000004,6,2\n1700000005,2,4\n'
        '1700000006,1,4\n1700000007,5,4\n1700000008,2,1\n'
        '1700000009,4,1\n1700000010,5,6\n'
    )


def run_program():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    run_as_user(['cargo', 'run', '--release', '--quiet'])
    assert OUTPUT.is_file(), f'Expected output file {OUTPUT} does not exist.'
    with OUTPUT.open() as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f'Failed to parse {OUTPUT} as valid JSON: {e}')


def derive_expected():
    with (DATA_DIR / 'departments.csv').open(newline='') as f:
        departments = {row['dept_code']: row['dept_name'] for row in csv.DictReader(f)}
    with (DATA_DIR / 'users.csv').open(newline='') as f:
        users = list(csv.DictReader(f))

    incoming = {int(row['uid']): 0 for row in users}
    with (DATA_DIR / 'comms.log').open(newline='') as f:
        for row in csv.reader(f):
            receiver = int(row[2])
            if receiver in incoming:
                incoming[receiver] += 1

    result = [
        {'uid': int(row['uid']), 'name': row['name'], 'in_degree': incoming[int(row['uid'])]}
        for row in users
        if departments.get(row['dept_code']) == 'Investment'
    ]
    result.sort(key=lambda item: (-item['in_degree'], item['uid']))
    return result[:2]


def write_hidden_fixture():
    ids = set()
    while len(ids) < 6:
        ids.add(1000 + secrets.randbelow(900000))
    ids = list(ids)
    investment = sorted(ids[:4])
    retail, legal = ids[4], ids[5]

    with (DATA_DIR / 'departments.csv').open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows([
            ['dept_code', 'dept_name'],
            ['X9', 'Retail'],
            ['Q7', 'Investment'],
            ['L4', 'Legal'],
        ])

    user_rows = [
        [investment[0], 'HiddenAlpha', 'Q7'],
        [investment[1], 'HiddenBeta', 'Q7'],
        [investment[2], 'HiddenGamma', 'Q7'],
        [investment[3], 'HiddenDelta', 'Q7'],
        [retail, 'HiddenRetail', 'X9'],
        [legal, 'HiddenLegal', 'L4'],
    ]
    secrets.SystemRandom().shuffle(user_rows)
    with (DATA_DIR / 'users.csv').open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['uid', 'name', 'dept_code'])
        writer.writerows(user_rows)

    # The two leading Investment users tie, requiring UID-ascending tie-breaking.
    target_counts = {
        investment[0]: 7,
        investment[1]: 7,
        investment[2]: 4,
        investment[3]: 1,
        retail: 11,
        legal: 3,
    }
    all_ids = investment + [retail, legal]
    messages = []
    timestamp = 1800000000
    for receiver, count in target_counts.items():
        senders = [uid for uid in all_ids if uid != receiver]
        for i in range(count):
            messages.append([timestamp, senders[i % len(senders)], receiver])
            timestamp += 1
    secrets.SystemRandom().shuffle(messages)
    with (DATA_DIR / 'comms.log').open('w', newline='') as f:
        csv.writer(f).writerows(messages)


def test_rust_project_and_output():
    assert PROJECT.is_dir(), f'Expected Rust project directory {PROJECT} does not exist.'
    cargo_toml = PROJECT / 'Cargo.toml'
    main_rs = PROJECT / 'src' / 'main.rs'
    assert cargo_toml.is_file(), f'Expected {cargo_toml} to be a regular file.'
    assert main_rs.is_file(), f'Expected {main_rs} to be a regular file.'
    assert stat.S_ISREG(cargo_toml.stat().st_mode)
    assert stat.S_ISREG(main_rs.stat().st_mode)

    # Force a real release build from the submitted project rather than trusting
    # any pre-created output JSON or stale executable.
    run_as_user(['cargo', 'clean'])
    run_as_user(['cargo', 'build', '--release'])

    try:
        write_original_fixture()
        data = run_program()

        # Preserve the original verifier's structure and exact-content assertions.
        assert isinstance(data, list), f'Expected JSON root to be a list, but got {type(data).__name__}.'
        assert len(data) == 2, f'Expected exactly 2 elements in the JSON array, but got {len(data)}.'
        expected_first = {'uid': 2, 'name': 'Bob', 'in_degree': 5}
        assert data[0] == expected_first, f'First element in JSON does not match expected. Got {data[0]}, expected {expected_first}.'
        expected_second = {'uid': 4, 'name': 'Diana', 'in_degree': 3}
        assert data[1] == expected_second, f'Second element in JSON does not match expected. Got {data[1]}, expected {expected_second}.'

        write_hidden_fixture()
        expected_hidden = derive_expected()
        hidden_data = run_program()
        assert hidden_data == expected_hidden, (
            f'Program did not correctly parse and analyze a second input dataset. '
            f'Got {hidden_data}, expected {expected_hidden}.'
        )
    finally:
        write_original_fixture()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
