#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import shutil
import subprocess

import pytest

SCRIPT = '/home/user/process_data.sh'
DATA_DIR = '/home/user/data'
OUTPUT_DIR = '/home/user/output'
OUTPUT_FILE = '/home/user/output/clean_rolling_tx.csv'

ORIGINAL_FILES = {
    'export_A.csv': '''tx_id,user_id,amount,timestamp,retry_flag
T01,U1,100,10,0
T02,U1,-50,11,0
T03,U2,200,10,0
T-06,U1,100,20,0
''',
    'export_B.csv': '''tx_id,user_id,amount,timestamp,retry_flag
T04,U1,50,15,0
T05,U2,300,15,0
T07,U3,50,5,0
T08,U3,50,6,0
T09,U3,50,7,0
''',
    'export_retry.csv': '''tx_id,user_id,amount,timestamp,retry_flag
T01,U1,100,12,1
T03,U2,200,10,1
T08,U3,50,6,2
''',
}

MODIFIED_FILES = {
    'export_A.csv': '''tx_id,user_id,amount,timestamp,retry_flag
X1,alpha,4,2,0
DUP1,alpha,5,1,0
NEG,alpha,-3,5,0
BAD-ID,alpha,100,6,0
W1,beta,8,20,0
WITH_UNDER,beta,100,21,0
''',
    'export_B.csv': '''tx_id,user_id,amount,timestamp,retry_flag
DUP1,alpha,12,10,0
TIE1,beta,6,3,1
ZERO,beta,0,7,0
X2,alpha,7,15,0
INTRA,gamma,2,1,0
INTRA,gamma,9,4,0
''',
    'export_retry.csv': '''tx_id,user_id,amount,timestamp,retry_flag
DUP1,alpha,99,9,9
TIE1,beta,11,3,4
W2,beta,1,2,0
G2,gamma,3,8,0
''',
}


def install_inputs(files):
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    os.makedirs(DATA_DIR)
    for name, content in files.items():
        with open(os.path.join(DATA_DIR, name), 'w', newline='') as f:
            f.write(content)


def run_script():
    subprocess.run([SCRIPT], cwd='/home/user', check=True, timeout=20)


def derive_expected(files):
    deduplicated = {}
    for name in ('export_A.csv', 'export_B.csv', 'export_retry.csv'):
        for row in csv.DictReader(io.StringIO(files[name])):
            if not re.fullmatch(r'[A-Za-z0-9]+', row['tx_id']):
                continue
            amount = int(row['amount'])
            if amount <= 0:
                continue
            rank = (int(row['timestamp']), int(row['retry_flag']))
            previous = deduplicated.get(row['tx_id'])
            if previous is None or rank > previous[0]:
                deduplicated[row['tx_id']] = (rank, row, amount)

    records = [entry[1:] for entry in deduplicated.values()]
    records.sort(key=lambda entry: (entry[0]['user_id'], int(entry[0]['timestamp'])))

    lines = ['tx_id,user_id,amount,rolling_sum']
    previous_amount = {}
    for row, amount in records:
        rolling = amount + previous_amount.get(row['user_id'], 0)
        previous_amount[row['user_id']] = amount
        lines.append(f"{row['tx_id']},{row['user_id']},{row['amount']},{rolling}")
    return '\n'.join(lines)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} is missing.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'


def test_original_pipeline_output():
    install_inputs(ORIGINAL_FILES)
    run_script()

    assert os.path.isdir(OUTPUT_DIR), f'{OUTPUT_DIR} directory is missing.'
    assert os.path.isfile(OUTPUT_FILE), f'Output file {OUTPUT_FILE} is missing.'

    expected_content = '''tx_id,user_id,amount,rolling_sum
T01,U1,100,100
T04,U1,50,150
T03,U2,200,200
T05,U2,300,500
T07,U3,50,50
T08,U3,50,100
T09,U3,50,100'''
    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()
    assert content == expected_content, f'Content of {OUTPUT_FILE} does not match the expected output.'


def test_pipeline_on_modified_inputs():
    expected_content = derive_expected(MODIFIED_FILES)
    install_inputs(MODIFIED_FILES)
    run_script()

    assert os.path.isdir(OUTPUT_DIR), 'The script did not create the output directory.'
    assert os.path.isfile(OUTPUT_FILE), 'The script did not create the output CSV.'
    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()
    assert content == expected_content, 'The script failed on modified ETL inputs.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
