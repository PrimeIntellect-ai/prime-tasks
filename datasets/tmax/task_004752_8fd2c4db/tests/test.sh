#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
INPUT_DIR = HOME / 'customer_feedback'
PROCESSED_FILE = HOME / 'processed_data.csv'
REJECTED_FILE = HOME / 'rejected_data.csv'
HEADER = ['id', 'name', 'email', 'phone', 'rating', 'comments']

EXPECTED_PROCESSED = [
    ['101', 'Alice Smith', '***@test.com', '********7890', '5', 'Great service!'],
    ['201', 'José García', '***@empresa.es', '*********** 456', '4', 'Buen trabajo'],
    ['301', 'Björn', '***@sverige.se', '********5 67', '1', 'Terrible!'],
    ['302', 'Müller', '***@deutschland.de', '123', '5', 'Sehr gut'],
    ['303', 'Empty Phone', '***@phone.com', '', '2', 'No phone provided'],
]
EXPECTED_REJECTED = [
    ['102', 'Bob Jones', 'bob_jones_no_domain', '555-9999', '4', 'Okay'],
    ['103', 'Charlie', 'charlie@domain.com', '987654321', '6', 'Too high rating'],
    ['abc', 'Bad ID', 'bad@id.com', '1111', '3', 'ID is letters'],
]


def read_csv_utf8(path):
    assert path.exists(), f'{path} does not exist'
    try:
        with path.open('r', encoding='utf-8', newline='') as f:
            return list(csv.reader(f))
    except UnicodeDecodeError as exc:
        raise AssertionError(f'{path} is not strictly UTF-8') from exc


def assert_output(path, expected):
    data = read_csv_utf8(path)
    assert data, f'{path} is empty'
    assert data[0] == HEADER, f'Incorrect header in {path}: {data[0]}'
    rows = data[1:]
    assert len(rows) == len(expected), (
        f'Expected {len(expected)} rows in {path}, got {len(rows)}'
    )
    assert {tuple(r) for r in rows} == {tuple(r) for r in expected}, (
        f'Incorrect rows in {path}: {rows}'
    )


# Preserve the original verifier's checks for the supplied fixture.
assert_output(PROCESSED_FILE, EXPECTED_PROCESSED)
assert_output(REJECTED_FILE, EXPECTED_REJECTED)

# The requested artifact must be a Python script, not just prewritten CSV files.
candidates = sorted(
    p for p in HOME.rglob('*.py')
    if p.is_file() and INPUT_DIR not in p.parents
)
assert candidates, 'No Python processing script exists under /home/user'


def is_valid(row):
    ident, _, email, _, rating, _ = row
    valid_id = bool(ident) and all('0' <= ch <= '9' for ch in ident)
    valid_email = email.count('@') == 1 and '.' in email.split('@', 1)[1]
    try:
        rating_value = int(rating)
        valid_rating = rating.strip() == rating and 1 <= rating_value <= 5
    except ValueError:
        valid_rating = False
    return valid_id and valid_email and valid_rating


def expected_outputs(rows):
    processed = []
    rejected = []
    for source in rows:
        row = list(source)
        if not is_valid(row):
            rejected.append(row)
            continue
        _, domain = row[2].split('@', 1)
        row[2] = '***@' + domain
        if len(row[3]) > 4:
            row[3] = '*' * (len(row[3]) - 4) + row[3][-4:]
        processed.append(row)
    return processed, rejected


def write_fixture(path, rows, encoding):
    with path.open('w', encoding=encoding, newline='') as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows)


def install_dynamic_fixture():
    token = secrets.token_hex(6)
    base = str(400000 + secrets.randbelow(500000))
    files = [
        ('file1.csv', 'utf-8', [
            [base + '1', 'Zoë, Tester', f'user.{token}@example.{token}.com', '12-34 5678', '3', 'Said "hello", thanks'],
            [base + '2', 'Bad At', f'a@b@{token}.com', '555-0000', '2', 'Email has two at signs'],
        ]),
        ('file2.csv', 'iso-8859-1', [
            [base + '3', 'José Peña', f'jose@empresa-{token}.es', '+34 600 987 654', '5', 'Información útil'],
            ['12x' + token, 'Bad ID', f'bad@{token}.net', '1111', '4', 'Raw invalid row'],
        ]),
        ('file3.csv', 'utf-16', [
            [base + '4', 'Björn', f'bjorn@north-{token}.se', '1234', '1', 'UTF-16 row'],
            [base + '5', 'Empty Phone', f'empty@phone-{token}.org', '', '2', 'No phone'],
            [base + '6', 'Decimal Rating', f'rate@{token}.org', '99999', '3.0', 'Not an integer'],
            [base + '7', 'No Domain Dot', f'user@domain-{token}', '88888', '3', 'Missing dot'],
        ]),
        (f'extra_{token}.csv', 'utf-8', [
            [base + '8', 'Extra File', f'extra@all-{token}.csv', 'ABCDE', '4', 'All CSV files must be read'],
            ['', 'Empty ID', f'emptyid@{token}.com', 'secret-phone', '5', 'Must remain unmasked'],
        ]),
    ]

    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in INPUT_DIR.iterdir():
        if old.is_file() or old.is_symlink():
            old.unlink()
    all_rows = []
    for filename, encoding, rows in files:
        write_fixture(INPUT_DIR / filename, rows, encoding)
        all_rows.extend(rows)
    return expected_outputs(all_rows)


errors = []
passed = False
for script in candidates:
    expected_processed, expected_rejected = install_dynamic_fixture()
    PROCESSED_FILE.unlink(missing_ok=True)
    REJECTED_FILE.unlink(missing_ok=True)
    try:
        result = subprocess.run(
            ['python3', str(script)],
            cwd=str(HOME),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'exited {result.returncode}; stderr: {result.stderr[-1000:]}'
        )
        assert_output(PROCESSED_FILE, expected_processed)
        assert_output(REJECTED_FILE, expected_rejected)
        passed = True
        break
    except Exception as exc:
        errors.append(f'{script}: {exc}')

assert passed, 'No Python script correctly processed the changed inputs:\n' + '\n'.join(errors)
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
