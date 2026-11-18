#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import re

def compute_expected_output(raw_path):
    if not os.path.exists(raw_path):
        return []

    with open(raw_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # Calculate median views
    valid_views = []
    for r in rows:
        v = r.get('views', '')
        if v is not None and str(v).strip():
            try:
                valid_views.append(float(str(v).strip()))
            except ValueError:
                pass

    if valid_views:
        valid_views.sort()
        n = len(valid_views)
        if n % 2 == 1:
            median_views = valid_views[n//2]
        else:
            median_views = (valid_views[n//2 - 1] + valid_views[n//2]) / 2.0
        median_views = int(median_views) # round down
    else:
        median_views = 0

    expected = []
    for r in rows:
        text = r.get('text', '')
        if text is None or not str(text).strip():
            continue

        author = r.get('author', '')
        if author is None or not str(author).strip():
            author = "Unknown"

        views_str = r.get('views', '')
        if views_str is None or not str(views_str).strip():
            views = median_views
        else:
            try:
                views = int(float(str(views_str).strip()))
            except ValueError:
                views = median_views

        if views > 100000:
            continue

        # Clean text
        cleaned = str(text).lower()
        cleaned = re.sub(r'[^a-z0-9]', ' ', cleaned)
        tokens = [t for t in cleaned.split() if t]
        token_count = len(tokens)

        if token_count < 5 or token_count > 50:
            continue

        cleaned_text = ' '.join(tokens)

        expected.append({
            "doc_id": str(r.get('doc_id', '')),
            "cleaned_text": cleaned_text,
            "tokens": tokens,
            "token_count": token_count,
            "author": author,
            "views": views
        })

    return expected

def test_processed_dataset_exists():
    output_path = "/home/user/processed_dataset.jsonl"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

def test_processed_dataset_content():
    raw_path = "/home/user/raw_data.csv"
    output_path = "/home/user/processed_dataset.jsonl"

    assert os.path.exists(raw_path), f"Raw data file {raw_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    expected_data = compute_expected_output(raw_path)

    actual_data = []
    with open(output_path, 'r', encoding='utf-8') as f:
        for line_idx, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                actual_data.append(obj)
            except json.JSONDecodeError:
                assert False, f"Line {line_idx + 1} in {output_path} is not valid JSON."

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        # doc_id could be string or int in actual, but string is preferred. Compare as string.
        assert str(actual.get("doc_id", "")) == expected["doc_id"], f"Record {i}: Expected doc_id {expected['doc_id']}, got {actual.get('doc_id')}"
        assert actual.get("cleaned_text") == expected["cleaned_text"], f"Record {i}: Expected cleaned_text '{expected['cleaned_text']}', got '{actual.get('cleaned_text')}'"
        assert actual.get("tokens") == expected["tokens"], f"Record {i}: Expected tokens {expected['tokens']}, got {actual.get('tokens')}"
        assert actual.get("token_count") == expected["token_count"], f"Record {i}: Expected token_count {expected['token_count']}, got {actual.get('token_count')}"
        assert actual.get("author") == expected["author"], f"Record {i}: Expected author '{expected['author']}', got '{actual.get('author')}'"
        assert actual.get("views") == expected["views"], f"Record {i}: Expected views {expected['views']}, got {actual.get('views')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
