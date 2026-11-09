#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import stat
import subprocess
import sys

SCRIPT_PATH = '/home/user/find_similar.py'
CSV_PATH = '/home/user/customers.csv'
OUTPUT_PATH = '/home/user/similar_customers.txt'


def expected_output(csv_data):
    valid_rows = []
    reader = csv.DictReader(io.StringIO(csv_data))
    for row in reader:
        try:
            id_val = int(row['id'])
            age_val = int(row['age'])
            income_val = float(row['income'])
            score_val = float(row['spending_score'])

            if age_val > 0 and income_val >= 0 and 0 <= score_val <= 100:
                valid_rows.append({
                    'id': id_val,
                    'age': age_val,
                    'income': income_val,
                    'score': score_val,
                })
        except (ValueError, TypeError, KeyError):
            continue

    assert len(valid_rows) > 0, 'No valid rows found in the CSV.'

    min_age = min(r['age'] for r in valid_rows)
    max_age = max(r['age'] for r in valid_rows)
    min_inc = min(r['income'] for r in valid_rows)
    max_inc = max(r['income'] for r in valid_rows)
    min_score = min(r['score'] for r in valid_rows)
    max_score = max(r['score'] for r in valid_rows)

    def normalize(val, min_v, max_v):
        if max_v == min_v:
            return 0.0
        return (val - min_v) / (max_v - min_v)

    target_norm = (
        normalize(35, min_age, max_age),
        normalize(75000, min_inc, max_inc),
        normalize(50, min_score, max_score),
    )

    distances = []
    for row in valid_rows:
        row_norm = (
            normalize(row['age'], min_age, max_age),
            normalize(row['income'], min_inc, max_inc),
            normalize(row['score'], min_score, max_score),
        )
        distance = math.sqrt(sum(
            (row_norm[i] - target_norm[i]) ** 2 for i in range(3)
        ))
        distances.append((distance, row['id']))

    distances.sort(key=lambda item: item[0])
    return ','.join(str(item[1]) for item in distances[:3])


def run_case(csv_data):
    expected = expected_output(csv_data)
    with open(CSV_PATH, 'w', newline='') as csv_file:
        csv_file.write(csv_data)

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, '-I', '-S', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed when executed with zero-dependency Python.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'
    assert os.path.exists(CSV_PATH), f'Input file {CSV_PATH} does not exist.'

    with open(CSV_PATH, 'r', newline='') as csv_file:
        assert csv_file.read() == csv_data, 'The script modified the input CSV.'
    with open(OUTPUT_PATH, 'r') as output_file:
        actual = output_file.read().strip()

    assert actual == expected, (
        'Output file content is incorrect.\n'
        f'Expected: {expected}\nGot: {actual}'
    )
    return actual


def make_random_case():
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 1000000), 10)
    valid = [(ids[0], 35, 75000, 50)]
    for customer_id in ids[1:]:
        valid.append((
            customer_id,
            rng.randint(18, 75),
            rng.randint(5000, 180000),
            rng.randint(0, 100),
        ))
    rng.shuffle(valid)

    rows = [','.join(map(str, row)) for row in valid]
    rows.extend([
        f'{rng.randint(1000001, 2000000)},-2,55000,40',
        f'{rng.randint(2000001, 3000000)},unknown,62000,55',
        f'{rng.randint(3000001, 4000000)},28,-1,45',
        f'{rng.randint(4000001, 5000000)},31,70000,101',
        f'{rng.randint(5000001, 6000000)},44,81000,',
        'not-an-id,40,90000,50',
    ])
    rng.shuffle(rows)
    return 'id,age,income,spending_score\n' + '\n'.join(rows) + '\n'


def test_similar_customers_output_and_pipeline():
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    mode = os.stat(SCRIPT_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_PATH} must be a regular Python script.'
    assert os.path.exists(CSV_PATH), f'Input file {CSV_PATH} does not exist.'

    with open(CSV_PATH, 'r', newline='') as csv_file:
        original_csv = csv_file.read()

    original_output = None
    try:
        # Preserve the original verifier's exact comparison, but require the
        # submitted script itself to create the output first.
        original_output = run_case(original_csv)

        # Unseen inputs and randomized IDs prevent a fixed answer from passing.
        run_case(make_random_case())
        run_case(make_random_case())
    finally:
        with open(CSV_PATH, 'w', newline='') as csv_file:
            csv_file.write(original_csv)
        if original_output is not None:
            with open(OUTPUT_PATH, 'w') as output_file:
                output_file.write(original_output)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
