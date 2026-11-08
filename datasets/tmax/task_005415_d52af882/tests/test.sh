#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os

OUTPUT_PATH = '/home/user/top_items.csv'
RATINGS_PATH = '/home/user/ratings.csv'


def calculate_expected_rows():
    with open(RATINGS_PATH, 'r', newline='') as f:
        data = list(csv.DictReader(f))

    users = sorted({row['user_id'] for row in data})
    items = sorted({row['item_id'] for row in data})
    valid_ratings = []
    item_valid_sums = {item: 0.0 for item in items}
    item_valid_counts = {item: 0 for item in items}

    for row in data:
        try:
            value = float(row['rating'])
            if math.isnan(value):
                continue
        except (TypeError, ValueError):
            continue
        valid_ratings.append(value)
        item_valid_sums[row['item_id']] += value
        item_valid_counts[row['item_id']] += 1

    global_mean = sum(valid_ratings) / len(valid_ratings)
    bayesian_avgs = {
        item: (5.0 * global_mean + item_valid_sums[item]) /
              (5.0 + item_valid_counts[item])
        for item in items
    }

    vectors = {item: {user: 0.0 for user in users} for item in items}
    for row in data:
        try:
            value = float(row['rating'])
            if math.isnan(value):
                value = bayesian_avgs[row['item_id']]
        except (TypeError, ValueError):
            value = bayesian_avgs[row['item_id']]
        vectors[row['item_id']][row['user_id']] = value

    def cosine(left, right):
        dot = sum(left[user] * right[user] for user in users)
        left_norm = math.sqrt(sum(left[user] ** 2 for user in users))
        right_norm = math.sqrt(sum(right[user] ** 2 for user in users))
        if left_norm == 0 or right_norm == 0:
            return 0.0
        return dot / (left_norm * right_norm)

    target = 'I42'
    similarities = [
        (item, cosine(vectors[target], vectors[item]))
        for item in items if item != target
    ]
    similarities.sort(key=lambda pair: (-pair[1], pair[0]))
    return [[item, f'{similarity:.4f}'] for item, similarity in similarities[:3]]


def test_top_items_exists():
    assert os.path.isfile(OUTPUT_PATH), (
        f'The output file {OUTPUT_PATH} does not exist. '
        'Did your Go program write to the correct path?'
    )


def test_top_items_content():
    assert os.path.isfile(OUTPUT_PATH), f'The output file {OUTPUT_PATH} does not exist.'

    with open(OUTPUT_PATH, 'r', newline='') as f:
        output_rows = list(csv.reader(f))

    expected_rows = calculate_expected_rows()
    assert len(output_rows) == len(expected_rows), (
        f'Expected {len(expected_rows)} rows in {OUTPUT_PATH}, '
        f'but found {len(output_rows)}.'
    )

    for i, (out_row, exp_row) in enumerate(zip(output_rows, expected_rows)):
        assert len(out_row) == 2, (
            f'Row {i + 1} in {OUTPUT_PATH} does not have exactly 2 columns: {out_row}'
        )
        out_item, out_sim = out_row
        exp_item, exp_sim = exp_row
        assert out_item == exp_item, (
            f"Row {i + 1}: Expected item '{exp_item}', but got '{out_item}'."
        )
        assert out_sim == exp_sim, (
            f"Row {i + 1}: Expected similarity '{exp_sim}' for item "
            f"'{exp_item}', but got '{out_sim}'."
        )
TEST_EOF

if (
    test -f /home/user/process.go &&
    rm -f /home/user/top_items.csv &&
    cd /home/user &&
    go run /home/user/process.go &&
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
