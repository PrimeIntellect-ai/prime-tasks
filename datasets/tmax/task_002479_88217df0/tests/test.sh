#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pandas as pd
import numpy as np

SOURCE = '/home/user/recommender.c'
BINARY = '/home/user/recommender'
OUTPUT = '/home/user/recommendations.txt'
DATASET = '/app/items.csv'
TARGET = np.array([12.5, 45.2, 8.9, 101.3, 55.0])
TARGET_ARGS = ['12.5', '45.2', '8.9', '101.3', '55.0']


def expected_recommendations():
    assert os.path.exists(DATASET), f'Dataset file not found at {DATASET}'
    df = pd.read_csv(DATASET)
    for col in ['f1', 'f2', 'f3', 'f4', 'f5']:
        df[col] = df[col].fillna(df[col].mean())
    features = df[['f1', 'f2', 'f3', 'f4', 'f5']].to_numpy(dtype=float)
    df['dist'] = np.linalg.norm(features - TARGET, axis=1)
    return df.nsmallest(10, 'dist')['item_id'].astype(int).tolist()


def parse_recommendations(text):
    lines = text.splitlines()
    assert len(lines) == 10, f'Expected exactly 10 recommendation lines, got {len(lines)}: {lines}'
    assert all(re.fullmatch(r'[0-9]+', line) for line in lines), \
        f'Each line must contain exactly one integer item_id: {lines}'
    values = [int(line) for line in lines]
    assert len(set(values)) == 10, f'Recommendations must contain 10 distinct item_ids: {values}'
    return values


def check_predictions(predictions, expected, context):
    # Preserve the original overlap assertion.
    intersection = len(set(expected).intersection(set(predictions[:10])))
    assert intersection >= 9, \
        f'{context}: intersection metric is {intersection}, expected >= 9. Expected: {expected}, got: {predictions}'
    # The instruction additionally requires closest-to-10th-closest ordering.
    assert predictions == expected, \
        f'{context}: recommendations are not the correctly ordered top 10. Expected: {expected}, got: {predictions}'


def run_program(path, expected, label):
    errors = []
    for args in ([], TARGET_ARGS):
        try:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            result = subprocess.run(
                [path] + args,
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            if result.returncode != 0:
                errors.append(f'args={args}: exit {result.returncode}, stderr={result.stderr!r}')
                continue

            if os.path.isfile(OUTPUT):
                with open(OUTPUT, 'r') as f:
                    text = f.read()
            else:
                # A compliant shell invocation may redirect the C program's stdout.
                text = result.stdout

            try:
                predictions = parse_recommendations(text)
                check_predictions(predictions, expected, label)
            except AssertionError as exc:
                errors.append(f'args={args}: {exc}')
                continue

            with open(OUTPUT, 'w') as f:
                f.write('\n'.join(map(str, predictions)) + '\n')
            return
        except subprocess.TimeoutExpired:
            errors.append(f'args={args}: timed out')

    raise AssertionError(f'{label} did not produce valid recommendations when executed: ' + ' | '.join(errors))


def test_complete_c_recommender():
    expected = expected_recommendations()

    assert os.path.isfile(OUTPUT), f'Recommendations file not found at {OUTPUT}'
    with open(OUTPUT, 'r') as f:
        initial = parse_recommendations(f.read())
    check_predictions(initial, expected, 'existing recommendations.txt')

    assert os.path.isfile(SOURCE), f'C source file not found at {SOURCE}'
    assert os.path.getsize(SOURCE) > 0, f'C source file is empty: {SOURCE}'

    assert os.path.isfile(BINARY), f'Compiled recommender not found at {BINARY}'
    assert os.access(BINARY, os.X_OK), f'Recommender is not executable: {BINARY}'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'Recommender is not a compiled ELF executable: {BINARY}'

    # Execute the submitted compiled artifact and verify its ordered output.
    run_program(BINARY, expected, 'submitted executable')

    # Ensure the submitted C source itself compiles and implements the same behavior.
    rebuilt = '/tmp/recommender_from_submitted_source'
    build = subprocess.run(
        ['gcc', SOURCE, '-O2', '-o', rebuilt, '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f'Failed to compile {SOURCE}: {build.stderr}'
    run_program(rebuilt, expected, 'executable rebuilt from recommender.c')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
