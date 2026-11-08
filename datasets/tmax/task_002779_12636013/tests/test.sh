#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess

import pytest

PROCESSOR = '/home/user/processor.py'
INPUT_FILE = '/home/user/data/users.csv'
OUTPUT_FILE = '/home/user/output.json'

EXPECTED_SOURCE = [
    {'id': '1', 'name': 'Alice', 'metadata': {'preferences': {'theme': 'dark'}}},
    {'id': '2', 'name': 'Bob', 'metadata': {'preferences': {'theme': 'light'}}},
    {'id': '3', 'name': 'Charlie', 'metadata': {'account_type': 'guest'}},
    {'id': '4', 'name': 'Dave', 'metadata': {'preferences': {'theme': 'dark'}}},
    {'id': '5', 'name': 'Eve', 'metadata': {'preferences': {}}},
]


def read_source():
    with open(INPUT_FILE, 'r', newline='') as f:
        rows = list(csv.DictReader(f))
    return [
        {'id': row['id'], 'name': row['name'], 'metadata': json.loads(row['metadata'])}
        for row in rows
    ]


def expected_output_from_source():
    return [
        {
            'id': row['id'],
            'name': row['name'],
            'theme': row['metadata'].get('preferences', {}).get('theme', 'light'),
        }
        for row in read_source()
    ]


@pytest.fixture(scope='session', autouse=True)
def run_processor():
    assert os.path.isfile(PROCESSOR), f'The processor script {PROCESSOR} does not exist.'
    assert read_source() == EXPECTED_SOURCE, 'The input CSV was modified.'

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        ['python3', PROCESSOR],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'processor.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert read_source() == EXPECTED_SOURCE, 'processor.py modified the input CSV.'


def test_output_json_exists_and_valid():
    output_file = '/home/user/output.json'
    assert os.path.isfile(output_file), f'The output file {output_file} does not exist.'

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {output_file} does not contain valid JSON.')

    assert isinstance(data, list), 'The output JSON should be a list of user objects.'
    assert len(data) == 5, f'The output JSON should contain exactly 5 users, but found {len(data)}.'


def test_output_json_content():
    output_file = '/home/user/output.json'
    assert os.path.isfile(output_file), f'The output file {output_file} does not exist.'

    with open(output_file, 'r') as f:
        data = json.load(f)

    users_by_id = {str(user.get('id')): user for user in data}

    # Check Charlie (id 3)
    assert '3' in users_by_id, "User with id '3' (Charlie) is missing from the output."
    assert users_by_id['3'].get('theme') == 'light', "User with id '3' (Charlie) should have theme 'light'."

    # Check Eve (id 5)
    assert '5' in users_by_id, "User with id '5' (Eve) is missing from the output."
    assert users_by_id['5'].get('theme') == 'light', "User with id '5' (Eve) should have theme 'light'."

    assert data == expected_output_from_source(), (
        'The output JSON must contain every CSV user in order with the correct id, name, and theme.'
    )


def test_bug_report_txt():
    bug_report_file = '/home/user/bug_report.txt'
    assert os.path.isfile(bug_report_file), f'The file {bug_report_file} does not exist.'

    with open(bug_report_file, 'r') as f:
        content = f.read().strip()

    assert content == '3', f"The bug_report.txt should contain exactly '3', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
