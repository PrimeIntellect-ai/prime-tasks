#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists():
    """Verify that the report file was created at the expected location."""
    report_path = '/home/user/report.txt'
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

def test_report_format_and_content():
    """Verify the content of the report matches the expected top 3 employees and their PageRank scores."""
    report_path = '/home/user/report.txt'

    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content, "The report file is empty."

    lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in the report, found {len(lines)}."

    # Expected output based on the filtered subgraph and networkx.pagerank defaults
    expected_lines = [
        "emp_A: 0.3541",
        "emp_E: 0.2289",
        "emp_B: 0.2185"
    ]

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, (
            f"Line {i+1} mismatch.\n"
            f"Expected: '{expected}'\n"
            f"Got: '{lines[i]}'\n"
            "Ensure you filtered out deleted transactions correctly, built the subgraph with the right entities, "
            "and sorted by score (descending) then employee_id (alphabetically)."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
