#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import runpy
import secrets

import pandas as pd

PIPELINE = '/home/user/pipeline.py'
USERS = '/home/user/users.csv'
TRANSACTIONS = '/home/user/transactions.csv'
OUTPUT = '/home/user/output.csv'


def run_pipeline_and_capture_output_frames():
    captured = []
    original_to_csv = pd.DataFrame.to_csv

    def checked_to_csv(self, path_or_buf=None, *args, **kwargs):
        try:
            destination = os.fspath(path_or_buf)
        except TypeError:
            destination = None
        if destination == OUTPUT:
            captured.append(self.copy())
        return original_to_csv(self, path_or_buf, *args, **kwargs)

    pd.DataFrame.to_csv = checked_to_csv
    try:
        runpy.run_path(PIPELINE, run_name='__main__')
    finally:
        pd.DataFrame.to_csv = original_to_csv

    return captured


def assert_nullable_integer_output_frame(captured):
    assert captured, f'{PIPELINE} did not write {OUTPUT} with pandas DataFrame.to_csv'
    frame = captured[-1]
    assert 'item_id' in frame.columns, 'The DataFrame written to output.csv has no item_id column'
    dtype = frame['item_id'].dtype
    assert isinstance(dtype, pd.api.extensions.ExtensionDtype), (
        f'item_id must use a pandas nullable extension dtype before serialization, got {dtype}'
    )
    assert pd.api.types.is_integer_dtype(dtype), (
        f'item_id must use pandas nullable integer dtype, got {dtype}'
    )
    assert frame['item_id'].isna().any(), 'The pipeline did not preserve users with missing items'


def test_pipeline_executes_on_unseen_inputs_with_nullable_integer_dtype():
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is missing or is not a regular file'

    with open(PIPELINE, 'rb') as f:
        compile(f.read(), PIPELINE, 'exec')

    with open(USERS, 'rb') as f:
        original_users = f.read()
    with open(TRANSACTIONS, 'rb') as f:
        original_transactions = f.read()

    base = secrets.randbelow(700000) + 200000
    user_ids = [base + offset for offset in (1, 13, 29, 47, 71)]
    item_ids = [
        secrets.randbelow(800000) + 1000000,
        secrets.randbelow(800000) + 2000000,
        secrets.randbelow(800000) + 3000000,
    ]
    names = ['TestAlpha', 'TestBeta', 'TestGamma', 'TestDelta', 'TestEpsilon']

    try:
        with open(USERS, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['user_id', 'name'])
            writer.writerows(zip(user_ids, names))

        with open(TRANSACTIONS, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['user_id', 'item_id'])
            writer.writerows([
                [user_ids[0], item_ids[0]],
                [user_ids[2], item_ids[1]],
                [user_ids[4], item_ids[2]],
            ])

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        captured = run_pipeline_and_capture_output_frames()
        assert os.path.isfile(OUTPUT), f'Executing {PIPELINE} did not create {OUTPUT}'
        assert_nullable_integer_output_frame(captured)

        with open(OUTPUT, newline='') as f:
            actual_rows = list(csv.reader(f))

        expected_rows = [
            ['user_id', 'name', 'item_id'],
            [str(user_ids[0]), names[0], str(item_ids[0])],
            [str(user_ids[1]), names[1], ''],
            [str(user_ids[2]), names[2], str(item_ids[1])],
            [str(user_ids[3]), names[3], ''],
            [str(user_ids[4]), names[4], str(item_ids[2])],
        ]
        assert actual_rows == expected_rows, (
            'The executed pipeline did not correctly merge unseen inputs while preserving '
            'integer item IDs and users with missing transactions'
        )
    finally:
        with open(USERS, 'wb') as f:
            f.write(original_users)
        with open(TRANSACTIONS, 'wb') as f:
            f.write(original_transactions)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_pipeline_and_capture_output_frames()


def test_output_csv_contents():
    output_path = '/home/user/output.csv'
    assert os.path.isfile(output_path), f"{output_path} is missing. Did you run the pipeline script?"

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "user_id,name,item_id",
        "1,Alice,101",
        "2,Bob,",
        "3,Charlie,105",
        "4,David,109"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {output_path} is incorrect. Expected '{expected}', got '{actual}'."


def test_corrupt_artifacts_txt_contents():
    txt_path = '/home/user/corrupt_artifacts.txt'
    assert os.path.isfile(txt_path), f"{txt_path} is missing."

    with open(txt_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_files = {"run_A.csv", "run_C.csv"}
    actual_files = set(lines)

    assert actual_files == expected_files, f"Expected {txt_path} to contain exactly {expected_files}, but got {actual_files}."
    assert len(lines) == 2, f"Expected exactly 2 lines in {txt_path}, but found {len(lines)} lines."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
