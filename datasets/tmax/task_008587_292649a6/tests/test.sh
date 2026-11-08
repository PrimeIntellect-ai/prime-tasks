#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import csv
import math
import hashlib
import pytest


def test_run_pipeline_sh_exists_and_executable():
    path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(path), f"File {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_artifacts_exist():
    csv_path = '/home/user/artifacts/processed_data.csv'
    json_path = '/home/user/artifacts/schema.json'
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."
    assert os.path.isfile(json_path), f"File {json_path} does not exist."


def test_schema_json():
    json_path = '/home/user/artifacts/schema.json'
    with open(json_path, 'r') as f:
        try:
            schema = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file.")

    assert 'customer_id' in schema, "schema.json does not contain 'customer_id' key."
    dtype_str = str(schema['customer_id']).lower()
    assert 'int' in dtype_str, f"customer_id dtype is not integer, got: {dtype_str}"


def test_processed_data_csv():
    csv_path = '/home/user/artifacts/processed_data.csv'
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) > 0, "processed_data.csv is empty."
    assert 'txn_id' in rows[0], "txn_id column missing."
    assert 'customer_id' in rows[0], "customer_id column missing."
    assert 'log_transaction_value' in rows[0], "log_transaction_value column missing."

    txn_2_found = False
    txn_1_found = False

    for row in rows:
        if row['txn_id'] == '2':
            txn_2_found = True
            assert row['customer_id'] == '0', f"Missing customer_id not filled with '0', got {row['customer_id']} instead."

        if row['txn_id'] == '1':
            txn_1_found = True
            try:
                actual_log = float(row['log_transaction_value'])
            except ValueError:
                pytest.fail(f"log_transaction_value for txn_id 1 is not a valid float: {row['log_transaction_value']}")

            expected_log = math.log(50.5 + 1)
            assert math.isclose(actual_log, expected_log, rel_tol=1e-4), \
                f"log_transaction_value calculated incorrectly for txn_id 1. Expected {expected_log}, got {actual_log}"

    assert txn_2_found, "txn_id 2 not found in processed_data.csv."
    assert txn_1_found, "txn_id 1 not found in processed_data.csv."


def test_run_log_md5():
    csv_path = '/home/user/artifacts/processed_data.csv'
    log_path = '/home/user/artifacts/run_log.txt'

    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    hash_md5 = hashlib.md5()
    with open(csv_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    expected_md5 = hash_md5.hexdigest()

    with open(log_path, 'r') as f:
        log_content = f.read()

    assert expected_md5 in log_content, \
        f"run_log.txt does not contain the correct MD5 checksum of processed_data.csv. Expected {expected_md5} to be in the log."
TEST_EOF

cat << 'VALIDATE_EOF' > /tmp/validate_pipeline.py
import hashlib
import json
import os
import numpy as np
import pandas as pd
from pandas.api.types import is_integer_dtype

transactions_path = '/home/user/raw_data/transactions.csv'
customers_path = '/home/user/raw_data/customers.csv'
csv_path = '/home/user/artifacts/processed_data.csv'
schema_path = '/home/user/artifacts/schema.json'
log_path = '/home/user/artifacts/run_log.txt'

for path in (csv_path, schema_path, log_path):
    assert os.path.isfile(path), f'Missing artifact: {path}'

transactions = pd.read_csv(transactions_path)
customers = pd.read_csv(customers_path)
expected = pd.merge(transactions, customers, on='customer_id', how='left')
expected['customer_id'] = expected['customer_id'].fillna(0).astype('int64')
expected['log_transaction_value'] = np.log1p(expected['transaction_value'])

actual = pd.read_csv(csv_path)
assert list(actual.columns) == list(expected.columns), (
    f'Output columns differ: expected {list(expected.columns)}, got {list(actual.columns)}'
)
assert len(actual) == len(expected), f'Expected {len(expected)} rows, got {len(actual)}'
pd.testing.assert_frame_equal(actual, expected, check_dtype=True, check_exact=False, rtol=1e-10, atol=1e-12)
assert is_integer_dtype(actual['customer_id'].dtype), actual['customer_id'].dtype

with open(schema_path, 'r') as f:
    schema = json.load(f)
expected_schema = {column: str(dtype) for column, dtype in expected.dtypes.items()}
assert schema == expected_schema, f'Expected schema {expected_schema}, got {schema}'

with open(csv_path, 'rb') as f:
    digest = hashlib.md5(f.read()).hexdigest()
with open(log_path, 'r') as f:
    log = f.read()
assert digest in log, f'run_log.txt does not contain current CSV MD5 {digest}'
VALIDATE_EOF

if bash << 'CHECK_EOF'
set -e
backup_dir=$(mktemp -d)
cp /home/user/raw_data/transactions.csv "$backup_dir/transactions.csv"
cp /home/user/raw_data/customers.csv "$backup_dir/customers.csv"

restore_raw() {
    cp "$backup_dir/transactions.csv" /home/user/raw_data/transactions.csv
    cp "$backup_dir/customers.csv" /home/user/raw_data/customers.csv
}
trap restore_raw EXIT

# Execute the submitted pipeline from a clean artifact directory on the original data.
rm -rf /home/user/artifacts/*
runuser -u user -- bash -c 'cd /home/user && ./run_pipeline.sh'
test -x /home/user/venv/bin/python
python3 -m pytest /tmp/test_final_state.py -x --tb=short
/home/user/venv/bin/python /tmp/validate_pipeline.py

# Exercise the pipeline on verifier-generated IDs so fixed, fabricated rows cannot pass.
python3 - << 'PY_EOF'
import secrets
base = secrets.randbelow(700000) + 200000
ids = [base, base + 7, base + 19]
with open('/home/user/raw_data/transactions.csv', 'w') as f:
    f.write('txn_id,customer_id,transaction_value\n')
    f.write(f'71,{ids[0]},3.25\n')
    f.write('72,,0.0\n')
    f.write(f'73,{ids[1]},87.125\n')
    f.write(f'74,{ids[0]},999.5\n')
    f.write(f'75,{ids[2]},12.75\n')
with open('/home/user/raw_data/customers.csv', 'w') as f:
    f.write('customer_id,customer_name,region\n')
    f.write(f'{ids[0]},Delta,West\n')
    f.write(f'{ids[1]},Echo,Central\n')
PY_EOF
rm -rf /home/user/artifacts/*
runuser -u user -- bash -c 'cd /home/user && ./run_pipeline.sh'
/home/user/venv/bin/python /tmp/validate_pipeline.py

# Restore the instructed inputs and leave freshly generated artifacts for them.
restore_raw
rm -rf /home/user/artifacts/*
runuser -u user -- bash -c 'cd /home/user && ./run_pipeline.sh'
python3 -m pytest /tmp/test_final_state.py -x --tb=short
/home/user/venv/bin/python /tmp/validate_pipeline.py
trap - EXIT
rm -rf "$backup_dir"
CHECK_EOF
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
