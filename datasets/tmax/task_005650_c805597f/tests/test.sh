#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
from collections import Counter
import pytest

def test_keyword_summary_exists():
    filepath = "/home/user/keyword_summary.txt"
    assert os.path.exists(filepath), f"Expected output file {filepath} does not exist."
    assert os.path.isfile(filepath), f"Expected {filepath} to be a file."

def test_keyword_summary_content():
    metadata_path = "/home/user/metadata.csv"
    citations_path = "/home/user/citations.txt"
    documents_path = "/home/user/documents.json"
    summary_path = "/home/user/keyword_summary.txt"

    assert os.path.exists(metadata_path), f"Missing {metadata_path}"
    assert os.path.exists(citations_path), f"Missing {citations_path}"
    assert os.path.exists(documents_path), f"Missing {documents_path}"
    assert os.path.exists(summary_path), f"Missing {summary_path}"

    # 1. Identify all papers that were published in 2022
    papers_2022 = set()
    with open(metadata_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get('year') == '2022':
                papers_2022.add(row.get('paper_id'))

    # 2. Filter this subset to find only the papers that cite P001
    citing_p001 = set()
    with open(citations_path, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[1] == 'P001':
                citing_p001.add(parts[0])

    target_papers = papers_2022.intersection(citing_p001)

    # 3 & 4. Extract keywords and aggregate
    keyword_counts = Counter()
    with open(documents_path, 'r', encoding='utf-8') as f:
        documents = json.load(f)
        for doc in documents:
            if doc.get('paper_id') in target_papers:
                for kw in doc.get('keywords', []):
                    keyword_counts[kw] += 1

    # Sort by count descending, then alphabetically
    sorted_keywords = sorted(keyword_counts.items(), key=lambda x: (-x[1], x[0]))

    expected_lines = [f"{count} {kw}" for kw, count in sorted_keywords]

    # Read actual output
    with open(summary_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {summary_path} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
