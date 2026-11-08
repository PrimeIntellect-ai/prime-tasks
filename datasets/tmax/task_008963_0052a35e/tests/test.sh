#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import re
import pytest
from collections import defaultdict

def compute_expected_results():
    # 1. Read and filter papers
    papers = {}
    with open("/home/user/dataset/papers.jsonl", "r") as f:
        for line in f:
            if not line.strip():
                continue
            paper = json.loads(line)
            abstract = paper.get("abstract", "")
            # Check for exact word "neural" (case-insensitive)
            if re.search(r'\bneural\b', abstract, re.IGNORECASE):
                papers[paper["paper_id"]] = {
                    "paper_id": paper["paper_id"],
                    "title": paper["title"],
                    "authors": [],
                    "in_degree": 0
                }

    # 2. Compute in-degrees
    in_degrees = defaultdict(int)
    with open("/home/user/dataset/citations.txt", "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                target = parts[1]
                in_degrees[target] += 1

    for pid in papers:
        papers[pid]["in_degree"] = in_degrees[pid]

    # 3. Map authors
    with open("/home/user/dataset/authors.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row["paper_id"]
            if pid in papers:
                papers[pid]["authors"].append(row["author_name"])

    for pid in papers:
        papers[pid]["authors"].sort()

    # 4. Rank and take top 3
    filtered_list = list(papers.values())
    filtered_list.sort(key=lambda x: (-x["in_degree"], x["paper_id"]))

    return filtered_list[:3]

def test_result_file_exists():
    assert os.path.isfile("/home/user/result.json"), "/home/user/result.json does not exist."

def test_result_json_validity_and_content():
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    with open(result_path, "r") as f:
        try:
            result_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{result_path} does not contain valid JSON.")

    assert isinstance(result_data, list), "The JSON output must be a list of objects."

    expected_data = compute_expected_results()

    assert len(result_data) == len(expected_data), f"Expected {len(expected_data)} items in the result, got {len(result_data)}."

    for i, (actual, expected) in enumerate(zip(result_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."
        assert actual.get("paper_id") == expected["paper_id"], f"Mismatch in paper_id at index {i}. Expected {expected['paper_id']}, got {actual.get('paper_id')}."
        assert actual.get("title") == expected["title"], f"Mismatch in title at index {i}."
        assert actual.get("in_degree") == expected["in_degree"], f"Mismatch in in_degree at index {i}."
        assert actual.get("authors") == expected["authors"], f"Mismatch in authors at index {i}. Ensure they are sorted alphabetically."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
