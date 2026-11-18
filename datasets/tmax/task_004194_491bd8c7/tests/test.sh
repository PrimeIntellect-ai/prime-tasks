#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import csv
from collections import Counter
import re

def test_output_file_exists():
    assert os.path.isfile("/home/user/output/processed_data.jsonl"), "The output file /home/user/output/processed_data.jsonl does not exist."

def test_output_contents():
    output_path = "/home/user/output/processed_data.jsonl"
    assert os.path.isfile(output_path), "Output file missing."

    # 1. Read and parse raw data to compute expected state
    docs_path = "/home/user/data/docs.csv"
    meta_path = "/home/user/data/meta.csv"

    docs = {}
    with open(docs_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            docs[row["doc_id"]] = row["text"]

    meta = {}
    with open(meta_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            meta[row["doc_id"]] = row["category"]

    # 2. Join and enforce schema
    valid_categories = {"news", "blog", "wiki"}
    joined_data = []
    for doc_id, text in docs.items():
        if doc_id in meta:
            try:
                doc_id_int = int(doc_id)
            except ValueError:
                continue

            category = meta[doc_id]
            if category not in valid_categories:
                continue

            joined_data.append({
                "doc_id": doc_id_int,
                "category": category,
                "text": text
            })

    # 3. Tokenize
    def tokenize(text):
        text = text.lower()
        text = re.sub(r'[^a-z0-9\s]', '', text)
        tokens = [t for t in text.split(' ') if t]
        return tokens

    all_tokens = []
    for item in joined_data:
        item["tokens"] = tokenize(item["text"])
        all_tokens.extend(item["tokens"])

    # 4. Feature Extraction
    token_counts = Counter(all_tokens)
    # Sort by frequency descending, then alphabetically ascending
    sorted_tokens = sorted(token_counts.items(), key=lambda x: (-x[1], x[0]))
    top_10_tokens = [t[0] for t in sorted_tokens[:10]]

    expected_results = []
    for item in joined_data:
        tf_vector = [item["tokens"].count(t) for t in top_10_tokens]
        l2_norm = math.sqrt(sum(x*x for x in tf_vector))
        item["tf_l2_norm"] = round(l2_norm, 4)
        expected_results.append(item)

    expected_results.sort(key=lambda x: x["doc_id"])

    # 5. Read output JSONL and verify
    actual_results = []
    with open(output_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                actual_results.append(data)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in processed_data.jsonl is not valid JSON.")

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} records, found {len(actual_results)}."

    # Check ordering
    actual_doc_ids = [item.get("doc_id") for item in actual_results]
    assert actual_doc_ids == sorted(actual_doc_ids), "The JSONL file is not sorted by doc_id in ascending order."

    for expected, actual in zip(expected_results, actual_results):
        assert "doc_id" in actual, "Missing 'doc_id' key in JSON object."
        assert "category" in actual, "Missing 'category' key in JSON object."
        assert "tokens" in actual, "Missing 'tokens' key in JSON object."
        assert "tf_l2_norm" in actual, "Missing 'tf_l2_norm' key in JSON object."

        assert isinstance(actual["doc_id"], int), f"doc_id must be an integer, got {type(actual['doc_id'])}."
        assert actual["doc_id"] == expected["doc_id"], f"Expected doc_id {expected['doc_id']}, got {actual['doc_id']}."

        assert actual["category"] == expected["category"], f"Expected category '{expected['category']}' for doc_id {expected['doc_id']}."

        assert isinstance(actual["tokens"], list), f"tokens must be a list for doc_id {expected['doc_id']}."
        assert actual["tokens"] == expected["tokens"], f"Tokens mismatch for doc_id {expected['doc_id']}."

        assert isinstance(actual["tf_l2_norm"], float), f"tf_l2_norm must be a float for doc_id {expected['doc_id']}."
        assert math.isclose(actual["tf_l2_norm"], expected["tf_l2_norm"], abs_tol=0.0002), \
            f"Expected tf_l2_norm {expected['tf_l2_norm']} for doc_id {expected['doc_id']}, got {actual['tf_l2_norm']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
