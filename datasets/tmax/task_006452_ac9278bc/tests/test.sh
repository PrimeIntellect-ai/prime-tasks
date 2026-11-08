#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess
from datetime import datetime

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA

SCRIPT = '/home/user/prepare_dataset.py'
RAW = '/home/user/raw_events.csv'
OUTPUT = '/home/user/processed_users.json'


def write_fixture(rows):
    pd.DataFrame(rows, columns=['user_id', 'timestamp', 'event_type']).to_csv(
        RAW, index=False, na_rep=''
    )


def run_script():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'prepare_dataset.py exited with {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT), f'Output JSON not found at {OUTPUT} after running the script.'


def validate_output():
    output_file = OUTPUT
    assert os.path.exists(output_file), f'Output JSON not found at {output_file}.'

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, 'Output file is not valid JSON.'

    assert isinstance(data, dict), 'The root JSON object must be a dictionary.'

    # Read the raw CSV to determine expected state
    raw_file = RAW
    assert os.path.exists(raw_file), f'Raw CSV missing at {raw_file}.'

    user_events = {}
    with open(raw_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row['user_id']
            ts = datetime.strptime(row['timestamp'], '%Y-%m-%d %H:%M:%S')
            ev = row['event_type'].strip()
            if uid not in user_events:
                user_events[uid] = []
            user_events[uid].append((ts, ev))

    # Sort chronologically
    for uid in user_events:
        user_events[uid].sort(key=lambda x: x[0])

    assert len(data) == len(user_events), f'Expected {len(user_events)} users, found {len(data)}.'

    # Infer the mapping from event_type to token ID.
    inferred_mapping = {'': 0}
    used_ids = {0}

    for uid_str, udata in data.items():
        assert uid_str in user_events, f'Unexpected user_id {uid_str} in output.'
        expected_events = user_events[uid_str]
        assert isinstance(udata, dict), f'Value for user {uid_str} must be an object.'

        assert 'tokens' in udata, f"Missing 'tokens' for user {uid_str}"
        assert 'embedding' in udata, f"Missing 'embedding' for user {uid_str}"

        tokens = udata['tokens']
        assert isinstance(tokens, list), f"'tokens' for user {uid_str} must be a list."
        assert len(tokens) == len(expected_events), f'Token count mismatch for user {uid_str}.'

        for i, (ts, ev) in enumerate(expected_events):
            token = tokens[i]
            assert isinstance(token, int) and not isinstance(token, bool), f'Token {token} is not a strict integer.'

            if ev == '':
                assert token == 0, f'Missing event type must be mapped to 0, but got {token} for user {uid_str}.'
            else:
                assert token != 0, f"Valid event type '{ev}' was incorrectly mapped to 0 for user {uid_str}."
                if ev in inferred_mapping:
                    assert inferred_mapping[ev] == token, f"Inconsistent mapping for event '{ev}': expected {inferred_mapping[ev]}, got {token}."
                else:
                    assert token not in used_ids, f"Token ID {token} for event '{ev}' is already used by another event."
                    inferred_mapping[ev] = token
                    used_ids.add(token)

        embedding = udata['embedding']
        assert isinstance(embedding, list), f"'embedding' for user {uid_str} must be a list."
        assert len(embedding) == 2, f"'embedding' for user {uid_str} must have exactly 2 elements."
        for val in embedding:
            assert isinstance(val, (int, float)), f'Embedding values must be numbers, got {type(val)}.'
            assert type(val) is float, f'Embedding values must be JSON floats, got {type(val)}.'
            assert math.isfinite(val), 'Embedding values must be finite.'
            assert val == round(val, 4), f'Embedding value {val} is not rounded to at most 4 decimal places.'

    # Verify that token IDs start from 1 and are contiguous (1, 2, 3...).
    valid_tokens = used_ids - {0}
    if valid_tokens:
        assert min(valid_tokens) == 1, f'Token IDs for valid events must start from 1. Found min {min(valid_tokens)}.'
        assert max(valid_tokens) == len(valid_tokens), 'Token IDs must be contiguous integers starting from 1.'

    # Recompute the requested user-token frequency matrix and PCA embeddings.
    ordered_users = sorted(user_events, key=int)
    n_tokens = max(used_ids) + 1
    matrix = np.zeros((len(ordered_users), n_tokens), dtype=float)
    for row_index, uid in enumerate(ordered_users):
        for token in data[uid]['tokens']:
            matrix[row_index, token] += 1

    expected = PCA(n_components=2, random_state=42).fit_transform(matrix)
    actual = np.asarray([data[uid]['embedding'] for uid in ordered_users], dtype=float)

    # PCA component signs are mathematically arbitrary, so accept a global sign
    # reversal independently for either component, but no other discrepancy.
    for component in range(2):
        same_sign_error = np.max(np.abs(actual[:, component] - expected[:, component]))
        flipped_sign_error = np.max(np.abs(actual[:, component] + expected[:, component]))
        assert min(same_sign_error, flipped_sign_error) <= 5.1e-5, (
            f'Embedding component {component} does not match PCA of the frequency matrix.'
        )


def test_processed_users_json_exists_and_valid():
    assert os.path.isfile(SCRIPT), f'Python script not found at {SCRIPT}.'
    with open(SCRIPT, 'rb') as f:
        source = f.read()
    assert source.strip(), 'prepare_dataset.py is empty.'
    compile(source, SCRIPT, 'exec')

    canonical = pd.DataFrame({
        'user_id': [1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 5],
        'timestamp': [
            '2023-01-01 10:00:00', '2023-01-01 10:05:00', '2023-01-01 10:10:00', '2023-01-01 10:15:00',
            '2023-01-01 09:00:00', '2023-01-01 09:30:00', '2023-01-01 10:00:00',
            '2023-01-02 11:00:00', '2023-01-02 11:01:00', '2023-01-02 11:02:00',
            '2023-01-03 14:00:00', '2023-01-03 15:00:00',
            '2023-01-04 16:00:00', '2023-01-04 16:05:00', '2023-01-04 16:10:00', '2023-01-04 16:15:00'
        ],
        'event_type': [
            'login', 'view', np.nan, 'click', 'login', 'purchase', 'logout',
            'view', 'view', 'click', np.nan, np.nan, 'login', 'view', 'purchase', 'logout'
        ]
    }).sample(frac=1, random_state=42).reset_index(drop=True)

    hidden = [
        (12, '2024-02-01 09:03:00', 'alpha'),
        (10, '2024-02-01 08:02:00', 'beta'),
        (13, '2024-02-01 10:05:00', None),
        (11, '2024-02-01 08:05:00', 'gamma'),
        (10, '2024-02-01 08:01:00', 'alpha'),
        (13, '2024-02-01 10:01:00', 'gamma'),
        (12, '2024-02-01 09:01:00', 'delta'),
        (11, '2024-02-01 08:03:00', 'beta'),
        (10, '2024-02-01 08:04:00', None),
        (13, '2024-02-01 10:03:00', 'beta'),
        (11, '2024-02-01 08:04:00', 'gamma'),
        (12, '2024-02-01 09:02:00', None),
        (10, '2024-02-01 08:06:00', 'alpha'),
        (13, '2024-02-01 10:02:00', 'delta'),
        (13, '2024-02-01 10:04:00', 'alpha'),
    ]

    # Exercise the submitted script on an unseen fixture, then restore the
    # original setup data and require the final artifact to be generated from it.
    write_fixture(hidden)
    try:
        run_script()
        validate_output()
    finally:
        write_fixture(canonical.itertuples(index=False, name=None))
        run_script()

    validate_output()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
