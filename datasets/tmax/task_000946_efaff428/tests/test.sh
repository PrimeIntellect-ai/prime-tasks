#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_schema_info_exists_and_correct():
    """Test that schema_info.txt contains the expected CREATE TABLE statements."""
    path = '/home/user/schema_info.txt'
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, 'r') as f:
        content = f.read().lower()

    expected_tables = ['authors', 'papers', 'paper_authors', 'citations']
    for table in expected_tables:
        # Check for the presence of the table creation statement (handling potential quotes)
        assert (f"create table {table}" in content or
                f"create table \"{table}\"" in content or
                f"create table `{table}`" in content), \
            f"Missing CREATE TABLE statement for '{table}' in {path}"

def test_longest_chain_exists_and_correct():
    """Test that longest_chain.txt contains the correct maximum simple-path depth."""
    path = '/home/user/longest_chain.txt'
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == '4', f"Expected longest chain to be 4, but got '{content}'"

def test_top_authors_exists_and_correct():
    """Test that top_authors.csv contains the correct aggregated data."""
    path = '/home/user/top_authors.csv'
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Year,AuthorName,TotalCitations,Rank",
        "2020,Bob,3,1",
        "2020,Charlie,3,2",
        "2021,Alice,1,1",
        "2021,Eve,1,2",
        "2022,Bob,1,1",
        "2022,Diana,1,2"
    ]

    assert lines == expected_lines, \
        f"CSV content does not match expected output.\nExpected: {expected_lines}\nGot: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
