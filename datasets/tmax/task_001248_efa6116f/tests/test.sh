#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import json
import math
import os
import re
import pytest

RAW_DATA_PATH = '/home/user/raw_data.csv'
CLEANED_DATA_PATH = '/home/user/cleaned_data.csv'
CORR_PATH = '/home/user/correlation.json'

def mean(xs):
    return sum(xs) / len(xs)

def pearson_corr(x, y):
    n = len(x)
    if n == 0: 
        return 0.0
    mean_x = mean(x)
    mean_y = mean(y)
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)

def process_raw_data():
    with open(RAW_DATA_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    processed = []
    for row in rows:
        # Clean review_id
        rid = row['review_id']
        if '.' in rid:
            rid = rid.split('.')[0]

        # Clean upvotes
        upv = row['upvotes']
        if not upv or upv.lower() == 'nan':
            upv = 0
        else:
            upv = int(float(upv))

        # Clean user_score
        score = int(row['user_score'])

        # Process text
        text = row['review_text']
        text = text.lower()
        text = re.sub(r'[^a-z0-9\s]', '', text)
        tokens = text.split()

        token_count = len(tokens)
        if token_count > 0:
            avg_token_length = sum(len(t) for t in tokens) / token_count
        else:
            avg_token_length = 0.0

        processed.append({
            'review_id': str(rid),
            'user_score': score,
            'upvotes': upv,
            'review_text': row['review_text'],
            'token_count': token_count,
            'avg_token_length': avg_token_length
        })
    return processed

def test_cleaned_data_exists():
    """Test that the cleaned dataset was saved to the correct location."""
    assert os.path.exists(CLEANED_DATA_PATH), f"The file {CLEANED_DATA_PATH} is missing."
    assert os.path.isfile(CLEANED_DATA_PATH), f"The path {CLEANED_DATA_PATH} exists but is not a file."

def test_correlation_exists():
    """Test that the correlation matrix JSON was saved to the correct location."""
    assert os.path.exists(CORR_PATH), f"The file {CORR_PATH} is missing."
    assert os.path.isfile(CORR_PATH), f"The path {CORR_PATH} exists but is not a file."

def test_cleaned_data_content():
    """Test the structure and values of the cleaned dataset."""
    expected_data = process_raw_data()

    with open(CLEANED_DATA_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The file {CLEANED_DATA_PATH} is empty.")

        expected_header = ['review_id', 'user_score', 'upvotes', 'review_text', 'token_count', 'avg_token_length']
        assert header == expected_header, f"Header mismatch in {CLEANED_DATA_PATH}. Expected {expected_header}, got {header}."

        rows = list(reader)
        assert len(rows) == len(expected_data), f"Row count mismatch. Expected {len(expected_data)} rows, got {len(rows)}."

        for i, (row, exp) in enumerate(zip(rows, expected_data)):
            assert row[0] == exp['review_id'], f"Row {i}: review_id mismatch. Expected {exp['review_id']}, got {row[0]}."
            assert int(row[1]) == exp['user_score'], f"Row {i}: user_score mismatch. Expected {exp['user_score']}, got {row[1]}."
            assert int(row[2]) == exp['upvotes'], f"Row {i}: upvotes mismatch. Expected {exp['upvotes']}, got {row[2]}."
            assert row[3] == exp['review_text'], f"Row {i}: review_text mismatch."
            assert int(row[4]) == exp['token_count'], f"Row {i}: token_count mismatch. Expected {exp['token_count']}, got {row[4]}."
            assert math.isclose(float(row[5]), exp['avg_token_length'], rel_tol=1e-3, abs_tol=1e-3), \
                f"Row {i}: avg_token_length mismatch. Expected {exp['avg_token_length']}, got {row[5]}."

def test_correlation_content():
    """Test the structure and values of the correlation matrix."""
    expected_data = process_raw_data()

    cols = ['user_score', 'upvotes', 'token_count', 'avg_token_length']
    data_dict = {
        'user_score': [d['user_score'] for d in expected_data],
        'upvotes': [d['upvotes'] for d in expected_data],
        'token_count': [d['token_count'] for d in expected_data],
        'avg_token_length': [d['avg_token_length'] for d in expected_data]
    }

    with open(CORR_PATH, 'r', encoding='utf-8') as f:
        try:
            agent_corr = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {CORR_PATH} does not contain valid JSON.")

    for c1 in cols:
        assert c1 in agent_corr, f"Column '{c1}' missing in correlation matrix."
        for c2 in cols:
            assert c2 in agent_corr[c1], f"Column '{c2}' missing in correlation matrix under '{c1}'."

            exp_val = pearson_corr(data_dict[c1], data_dict[c2])
            exp_val = round(exp_val, 4)
            agent_val = agent_corr[c1][c2]

            assert math.isclose(agent_val, exp_val, abs_tol=1e-3), \
                f"Correlation mismatch for {c1}-{c2}. Expected ~{exp_val}, got {agent_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
