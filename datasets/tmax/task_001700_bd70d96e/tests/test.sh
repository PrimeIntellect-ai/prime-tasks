#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import unicodedata
from collections import defaultdict

RAW_PATH = '/home/user/raw_reviews.csv'
JSONL_PATH = '/home/user/cleaned_reviews.jsonl'
STATS_PATH = '/home/user/monthly_stats.csv'


def expected_records():
    latest = {}
    with open(RAW_PATH, 'r', encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            try:
                rating = int(row['rating'])
            except (TypeError, ValueError):
                continue

            record = {
                'timestamp': row['timestamp'],
                'user_id': row['user_id'],
                'review_text': unicodedata.normalize(
                    'NFKC', row['review_text'].replace('\r\n', ' ').replace('\n', ' ')
                ),
                'rating': rating,
            }
            previous = latest.get(record['user_id'])
            if previous is None or record['timestamp'] > previous['timestamp']:
                latest[record['user_id']] = record
    return latest


def expected_stats(records):
    grouped = defaultdict(list)
    for record in records.values():
        grouped[record['timestamp'][:7]].append(record)

    result = []
    for month in sorted(grouped):
        items = grouped[month]
        result.append([
            month,
            str(len(items)),
            round(sum(item['rating'] for item in items) / len(items), 2),
            round(sum(len(item['review_text']) for item in items) / len(items), 2),
        ])
    return result


def test_monthly_stats():
    assert os.path.isfile(STATS_PATH), f"File {STATS_PATH} is missing."

    with open(STATS_PATH, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) == 4, f"Expected 4 rows (including header) in {STATS_PATH}, found {len(rows)}"
    assert rows[0] == ['month', 'total_reviews', 'avg_rating', 'avg_review_length'], "Header is incorrect"

    def check_row(row, expected_month, expected_total, expected_rating, expected_len):
        assert len(row) == 4, f"Expected 4 columns, got {len(row)}"
        assert row[0] == expected_month, f"Expected month {expected_month}, got {row[0]}"
        assert row[1] == expected_total, f"Expected total_reviews {expected_total}, got {row[1]}"
        assert float(row[2]) == float(expected_rating), f"Expected avg_rating {expected_rating}, got {row[2]}"
        assert float(row[3]) == float(expected_len), f"Expected avg_review_length {expected_len}, got {row[3]}"

    # Retain the original concrete checks, correcting March's faithful length.
    check_row(rows[1], '2023-01', '2', '4.5', '20.0')
    check_row(rows[2], '2023-02', '2', '2.5', '8.5')
    check_row(rows[3], '2023-03', '1', '4.0', '23.0')

    derived = expected_stats(expected_records())
    assert len(rows[1:]) == len(derived)
    for actual, expected in zip(rows[1:], derived):
        check_row(actual, expected[0], expected[1], expected[2], expected[3])


def test_cleaned_reviews():
    assert os.path.isfile(JSONL_PATH), f"File {JSONL_PATH} is missing."

    with open(JSONL_PATH, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    assert len(lines) == 5, f"Expected 5 records in {JSONL_PATH}, found {len(lines)}"

    users = set()
    actual_by_user = {}
    required_keys = {'timestamp', 'user_id', 'review_text', 'rating'}

    for line in lines:
        record = json.loads(line)
        assert set(record.keys()) == required_keys, f"Incorrect keys in record: {record.keys()}"
        users.add(record['user_id'])
        assert record['user_id'] not in actual_by_user, f"Duplicate record for user {record['user_id']}"
        actual_by_user[record['user_id']] = record

        assert '\n' not in record['review_text'], f"Found newline in review_text for user {record['user_id']}"
        assert '\r' not in record['review_text'], f"Found carriage return in review_text for user {record['user_id']}"
        assert isinstance(record['rating'], int) and not isinstance(record['rating'], bool), \
            f"Rating for user {record['user_id']} is not an integer"
        assert record['review_text'] == unicodedata.normalize('NFKC', record['review_text']), \
            f"review_text for user {record['user_id']} is not NFKC normalized"

        if record['user_id'] == 'u4':
            assert len(record['review_text']) == 4, "Length of review_text for u4 should be 4 after NFKC normalization"
            assert record['review_text'] == 'café', "review_text for u4 is incorrect"

    assert users == {'u1', 'u2', 'u4', 'u5', 'u6'}, f"Expected users {{u1, u2, u4, u5, u6}}, found {users}"
    assert actual_by_user == expected_records(), "Cleaned records do not exactly match the derived expected records"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
