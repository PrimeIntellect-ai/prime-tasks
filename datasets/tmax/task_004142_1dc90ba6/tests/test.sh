#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess
from pathlib import Path

import pandas as pd


def test_bad_output_exists():
    path = '/home/user/bad_output.csv'
    assert os.path.isfile(path), f"Missing file: {path}. You were supposed to run buggy_join.py."


def test_fixed_join_py_exists_and_runs():
    path = '/home/user/fixed_join.py'
    assert os.path.isfile(path), f"Missing file: {path}. You need to write the corrected script."

    # Require the submitted script itself to produce the corrected output.
    output = '/home/user/fixed_output.csv'
    if os.path.lexists(output):
        os.unlink(output)
    result = subprocess.run(
        ['python3', path],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"fixed_join.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output), "fixed_join.py did not create /home/user/fixed_output.csv"


def test_fixed_output_correct():
    path = '/home/user/fixed_output.csv'
    assert os.path.isfile(path), f"Missing file: {path}. Your script must generate this file."

    expected_tokens = {
        'doc_1': '9007199254740995',
        'doc_3': '9007199254740997',
        'doc_4': '1048576',
        'doc_5': '9007199254740993'
    }

    with open(path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 5, f"Expected 5 rows in {path}, found {len(rows)}"

    doc_ids = [row.get('doc_id') for row in rows]
    expected_docs = ['doc_1', 'doc_2', 'doc_3', 'doc_4', 'doc_5']
    for d in expected_docs:
        assert d in doc_ids, f"Missing {d} in {path}"

    for row in rows:
        doc_id = row.get('doc_id')
        token_id = row.get('token_id', '').strip()

        if doc_id in expected_tokens:
            expected_val = expected_tokens[doc_id]
            assert token_id == expected_val, f"For {doc_id}, expected token_id '{expected_val}', got '{token_id}'"
        elif doc_id == 'doc_2':
            assert token_id in ('', '<NA>', 'NaN'), f"For doc_2, expected missing value representation, got '{token_id}'"


def test_precision_loss_docs_correct():
    path = '/home/user/precision_loss_docs.txt'
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        lines = f.readlines()

    corrupted_docs = {line.strip() for line in lines if line.strip()}
    expected_corrupted = {'doc_1', 'doc_3', 'doc_5'}

    assert corrupted_docs == expected_corrupted, f"Expected corrupted docs {expected_corrupted}, but got {corrupted_docs}"


def test_fixed_script_handles_unseen_inputs():
    root = Path('/home/user')
    paths = [
        root / 'docs.csv',
        root / 'tokens.csv',
        root / 'bad_output.csv',
        root / 'fixed_output.csv',
        root / 'precision_loss_docs.txt',
    ]
    backups = {p: p.read_bytes() if p.exists() else None for p in paths}

    nonce = secrets.token_hex(6)
    doc_ids = [f'unseen_{nonce}_{i}' for i in range(5)]
    large_1 = 2**53 + 2 * secrets.randbelow(100000) + 1
    large_2 = large_1 + 2
    large_3 = large_1 + 4
    expected_tokens = {
        doc_ids[0]: str(large_1),
        doc_ids[2]: str(large_2),
        doc_ids[3]: '1048579',
        doc_ids[4]: str(large_3),
    }

    try:
        with open(root / 'docs.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['doc_id', 'author'])
            for i, doc_id in enumerate(doc_ids):
                writer.writerow([doc_id, f'Author {nonce} {i}'])

        with open(root / 'tokens.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['doc_id', 'token_id'])
            for doc_id in (doc_ids[0], doc_ids[2], doc_ids[3], doc_ids[4]):
                writer.writerow([doc_id, expected_tokens[doc_id]])

        # Supply the corresponding buggy result in case the submitted workflow
        # performs the requested comparison while creating its fixed output.
        docs = pd.read_csv(root / 'docs.csv')
        tokens = pd.read_csv(root / 'tokens.csv')
        docs.merge(tokens, on='doc_id', how='left').to_csv(root / 'bad_output.csv', index=False)

        fixed_output = root / 'fixed_output.csv'
        if os.path.lexists(fixed_output):
            fixed_output.unlink()

        result = subprocess.run(
            ['python3', str(root / 'fixed_join.py')],
            cwd=str(root),
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"fixed_join.py failed on unseen inputs.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert fixed_output.is_file(), "fixed_join.py did not create fixed_output.csv on unseen inputs"

        with open(fixed_output, newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        assert reader.fieldnames == ['doc_id', 'author', 'token_id'], (
            f"Unexpected output columns: {reader.fieldnames}"
        )
        assert len(rows) == len(doc_ids), f"Expected {len(doc_ids)} joined rows, got {len(rows)}"
        assert [row['doc_id'] for row in rows] == doc_ids, "The left-join row order or document set is incorrect"

        for i, row in enumerate(rows):
            assert row['author'] == f'Author {nonce} {i}', f"Incorrect author for {row['doc_id']}"
            token = row['token_id'].strip()
            if row['doc_id'] == doc_ids[1]:
                assert token in ('', '<NA>', 'NaN'), f"Expected a missing token, got '{token}'"
            else:
                assert token == expected_tokens[row['doc_id']], (
                    f"Token precision was not preserved for {row['doc_id']}: "
                    f"expected {expected_tokens[row['doc_id']]}, got {token}"
                )
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.lexists(path):
                    path.unlink()
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
