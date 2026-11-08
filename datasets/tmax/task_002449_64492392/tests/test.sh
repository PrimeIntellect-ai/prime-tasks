#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

SCRIPT_PATH = Path('/home/user/process.py')
CSV_PATH = Path('/home/user/clean_users.csv')
RUN1_PATH = Path('/home/user/data/users_run1.csv')
RUN2_PATH = Path('/home/user/data/users_run2.csv')
BACKUP_PATH = Path('/home/user/cron_backup.txt')
CRON_PATTERN = re.compile(r'^0\s+2\s+\*\s+\*\s+\*\s+/home/user/process\.py\s*$')


def run_process_script():
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', str(SCRIPT_PATH)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed when executed as user (exit {result.returncode}). '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def read_output_rows():
    assert CSV_PATH.is_file(), f'The output file {CSV_PATH} does not exist.'
    with CSV_PATH.open('r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f'The file {CSV_PATH} is empty.')
        rows = list(reader)
    return headers, rows


def test_process_script_exists_and_executable():
    """Verify that the process.py script exists and is executable."""
    assert SCRIPT_PATH.is_file(), f'The script {SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'The script {SCRIPT_PATH} is not executable.'


def test_process_script_runs_on_supplied_inputs():
    """Actually execute the submitted ETL artifact on the supplied files."""
    if CSV_PATH.exists():
        CSV_PATH.unlink()
    run_process_script()
    assert CSV_PATH.is_file(), f'Executing {SCRIPT_PATH} did not create {CSV_PATH}.'


def test_clean_users_csv_exists_and_correct():
    """Verify the output CSV is correctly processed, sorted, deduplicated, and masked."""
    headers, rows = read_output_rows()

    expected_headers = ['user_id', 'name', 'email', 'signup_date']
    assert headers == expected_headers, f'Headers are incorrect. Expected {expected_headers}, got {headers}.'
    assert len(rows) == 5, f'Expected 5 rows in {CSV_PATH}, but got {len(rows)}.'

    user_ids = [int(row[0]) for row in rows]
    assert user_ids == [1, 2, 3, 4, 5], (
        f'Rows are not deduplicated or not sorted by user_id correctly. Got user_ids: {user_ids}.'
    )

    expected_data = {
        1: {'name': 'Alice Smith', 'email': '*********th@example.com', 'date': '2023-01-15'},
        2: {'name': 'Bob Jones', 'email': '****es@test.org', 'date': '2023-02-20'},
        3: {'name': 'Charlie Brown', 'email': '****wn@peanuts.com', 'date': '2023-03-10'},
        4: {'name': 'Diana Prince', 'email': '***na@themyscira.gov', 'date': '2022-12-05'},
        5: {'name': 'Ed', 'email': 'ed@short.com', 'date': '2023-05-12'},
    }

    for row in rows:
        assert len(row) == 4, f'Expected 4 columns, got row {row!r}.'
        uid = int(row[0])
        expected = expected_data[uid]
        assert row[1] == expected['name'], (
            f'Name was not preserved for user_id {uid}. Expected {expected["name"]}, got {row[1]}.'
        )
        assert row[2] == expected['email'], (
            f'Email masking failed for user_id {uid}. Expected {expected["email"]}, got {row[2]}.'
        )
        assert row[3] == expected['date'], (
            f'Date normalization failed for user_id {uid}. Expected {expected["date"]}, got {row[3]}.'
        )


def test_process_script_handles_runtime_generated_inputs():
    """Exercise the script on fresh inputs whose expected answers are derived here."""
    original_run1 = RUN1_PATH.read_bytes()
    original_run2 = RUN2_PATH.read_bytes()
    original_output = CSV_PATH.read_bytes() if CSV_PATH.exists() else None

    base = 10000 + secrets.randbelow(80000)
    tag = secrets.token_hex(4)
    headers = ['user_id', 'name', 'email', 'signup_date']
    run1 = [
        [base + 20, f'First Duplicate {tag}', f'alpha.{tag}@example.net', '11/09/2024'],
        [base + 1, f'Short Local {tag}', 'xy@short.test', '2021-07-03'],
    ]
    run2 = [
        [base + 20, f'Wrong Duplicate {tag}', f'wrong.{tag}@invalid.test', '01-01-2001'],
        [base + 4, f'Dash Date {tag}', f'beta{tag}@example.org', '12-05-2022'],
        [base + 2, f'Slash Date {tag}', f'gamma{tag}@example.com', '03/10/2023'],
    ]

    def write_input(path, rows):
        with path.open('w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            writer.writerows(rows)
        os.chown(path, 1000, 1000)

    def normalize_date(value):
        for fmt in ('%m/%d/%Y', '%Y-%m-%d', '%m-%d-%Y'):
            try:
                return datetime.strptime(value, fmt).strftime('%Y-%m-%d')
            except ValueError:
                pass
        raise AssertionError(f'Unrecognized test date {value!r}')

    def mask_email(value):
        local, domain = value.split('@', 1)
        if len(local) <= 2:
            return value
        return ('*' * (len(local) - 2)) + local[-2:] + '@' + domain

    expected_by_id = {}
    for row in run1 + run2:
        uid = int(row[0])
        if uid not in expected_by_id:
            expected_by_id[uid] = [
                str(uid), row[1], mask_email(row[2]), normalize_date(row[3])
            ]
    expected_rows = [expected_by_id[uid] for uid in sorted(expected_by_id)]

    try:
        write_input(RUN1_PATH, run1)
        write_input(RUN2_PATH, run2)
        if CSV_PATH.exists():
            CSV_PATH.unlink()

        run_process_script()
        actual_headers, actual_rows = read_output_rows()
        assert actual_headers == headers, f'Headers are incorrect on generated input: {actual_headers}'
        assert actual_rows == expected_rows, (
            'ETL output was incorrect on runtime-generated input. '
            f'Expected {expected_rows!r}, got {actual_rows!r}.'
        )
    finally:
        RUN1_PATH.write_bytes(original_run1)
        RUN2_PATH.write_bytes(original_run2)
        if original_output is None:
            if CSV_PATH.exists():
                CSV_PATH.unlink()
        else:
            CSV_PATH.write_bytes(original_output)


def test_cron_backup_correct():
    """Verify both the installed cron job and its saved backup."""
    assert BACKUP_PATH.is_file(), f'The cron backup file {BACKUP_PATH} does not exist.'
    backup_content = BACKUP_PATH.read_text(encoding='utf-8')

    backup_match = any(CRON_PATTERN.fullmatch(line.strip()) for line in backup_content.splitlines())
    assert backup_match, (
        f"Could not find the correct cron schedule in {BACKUP_PATH}. "
        "Expected a line matching '0 2 * * * /home/user/process.py'."
    )

    result = subprocess.run(
        ['crontab', '-u', 'user', '-l'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f'No readable crontab is installed for user: {result.stderr}'
    installed_match = any(CRON_PATTERN.fullmatch(line.strip()) for line in result.stdout.splitlines())
    assert installed_match, "The actual crontab for user does not contain '0 2 * * * /home/user/process.py'."
    assert backup_content == result.stdout, (
        f'{BACKUP_PATH} is not the saved output of the currently installed user crontab.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
