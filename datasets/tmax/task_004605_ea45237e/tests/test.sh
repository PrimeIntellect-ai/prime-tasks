#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import csv
import json
from collections import Counter

def test_top_templates_csv_exists():
    """Check that the output CSV file exists."""
    assert os.path.exists("/home/user/top_templates.csv"), "/home/user/top_templates.csv does not exist."
    assert os.path.isfile("/home/user/top_templates.csv"), "/home/user/top_templates.csv is not a file."

def test_top_templates_csv_content():
    """Check that the CSV contains the correct normalized templates and counts in the correct order."""
    # 1. Compute the expected results from the source data
    equations = []
    with open("/home/user/data/equations.jsonl", "r", encoding="utf-8") as f:
        for line in f:
            # Fix the specific malformed unicodes injected by the setup script
            # so we can use the standard json parser to extract the exact equation string.
            clean_line = line.replace("\\u123", "?").replace("\\uXYZW", "?")
            try:
                data = json.loads(clean_line)
                if "equation" in data:
                    equations.append(data["equation"])
            except json.JSONDecodeError:
                # Fallback to regex if there are other unexpected JSON errors
                m = re.search(r'"equation":\s*"((?:[^"\\]|\\.)*)"', line)
                if m:
                    # Unescape standard JSON escapes
                    eq_str = m.group(1).replace('\\"', '"').replace('\\\\', '\\')
                    equations.append(eq_str)

    assert len(equations) > 0, "Could not extract any equations from the source file to compute truth."

    # 2. Normalize and aggregate
    counts = Counter()
    for eq in equations:
        # Remove all whitespace
        eq_no_space = re.sub(r'\s+', '', eq)
        # Replace alphabetic sequences with VAR
        eq_var = re.sub(r'[a-zA-Z]+', 'VAR', eq_no_space)
        # Replace digit sequences (with optional decimal) with NUM
        eq_norm = re.sub(r'[0-9]+(?:\.[0-9]+)?', 'NUM', eq_var)
        counts[eq_norm] += 1

    # Sort descending by count, then ascending alphabetically by template
    expected_sorted = sorted(counts.items(), key=lambda x: (-x[1], x[0]))[:100]

    # 3. Read and validate the actual CSV
    actual = []
    with open("/home/user/top_templates.csv", "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["template", "count"], f"CSV header must be exactly ['template', 'count'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Expected 2 columns in row, got {len(row)}: {row}"
            actual.append((row[0], int(row[1])))

    # 4. Compare expected vs actual
    assert len(actual) == len(expected_sorted), f"Expected {len(expected_sorted)} rows (excluding header), got {len(actual)}"

    for i, (exp_tpl, exp_cnt) in enumerate(expected_sorted):
        act_tpl, act_cnt = actual[i]
        assert act_tpl == exp_tpl, f"Row {i+1} mismatch: expected template '{exp_tpl}', got '{act_tpl}'"
        assert act_cnt == exp_cnt, f"Row {i+1} mismatch: expected count {exp_cnt} for template '{exp_tpl}', got {act_cnt}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
