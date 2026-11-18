#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
from collections import defaultdict

def parse_raw_logs(file_path):
    """
    Parses the raw logs and returns a dictionary mapping code to a list of top 3 entries.
    Entries are dicts with keys: uid, action, latency, original_index
    """
    # Regex based on the exact requirements
    pattern = re.compile(
        r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] '
        r'\[(INFO|WARN|ERROR)\] '
        r'\[UID:([a-zA-Z0-9]+)\] '
        r'Action ([A-Z]+) resulted in code (\d{3})\. '
        r'Latency: (\d+)ms\. Msg: .*$'
    )

    extracted = defaultdict(list)
    with open(file_path, 'r') as f:
        for i, line in enumerate(f):
            match = pattern.match(line.strip())
            if match:
                level, uid, action, code, latency = match.groups()
                extracted[code].append({
                    'uid': uid,
                    'action': action,
                    'latency': int(latency),
                    'index': i
                })

    top_entries = {}
    for code, entries in extracted.items():
        # Sort by latency descending, then index ascending (to preserve order on tie)
        sorted_entries = sorted(entries, key=lambda x: (-x['latency'], x['index']))
        top_entries[code] = sorted_entries[:3]

    return top_entries

def test_final_report_exists():
    """Test that the final report file has been created."""
    report_path = '/home/user/final_report.md'
    assert os.path.exists(report_path), f"Final report not found at {report_path}"
    assert os.path.isfile(report_path), f"{report_path} is not a file"

def test_final_report_content():
    """Test that the final report contains the correctly extracted and formatted top 3 entries per code."""
    raw_logs_path = '/home/user/raw_logs.txt'
    report_path = '/home/user/final_report.md'

    # Recompute the expected top entries from the raw logs
    expected_top_entries = parse_raw_logs(raw_logs_path)

    with open(report_path, 'r') as f:
        report_content = f.read()

    assert "# System Latency and Status Report" in report_content, "Report is missing the required main header."

    # Verify each code's section and entries
    sorted_codes = sorted(expected_top_entries.keys(), key=lambda x: int(x))

    for code in sorted_codes:
        code_header = f"## Code: {code}"
        assert code_header in report_content, f"Report is missing header for {code_header}"

        # Extract the section for this code
        section_start = report_content.find(code_header)
        # Find next header or end of string
        next_header = report_content.find("## Code:", section_start + 1)
        if next_header == -1:
            section_text = report_content[section_start:]
        else:
            section_text = report_content[section_start:next_header]

        entries = expected_top_entries[code]
        for i, entry in enumerate(entries, start=1):
            expected_line = f"{i}. UID: {entry['uid']}, Action: {entry['action']}, Latency: {entry['latency']}ms"
            assert expected_line in section_text, (
                f"Missing or incorrectly formatted entry in {code_header} section.\n"
                f"Expected to find: '{expected_line}'"
            )

        # Check that there are no extra items (e.g. item 4)
        unexpected_line_start = f"{len(entries) + 1}."
        lines = [line.strip() for line in section_text.split('\n') if line.strip()]
        for line in lines:
            assert not line.startswith(unexpected_line_start), (
                f"Found unexpected extra entry in {code_header} section: {line}"
            )

def test_report_ordering():
    """Test that the codes are ordered in ascending numerical order in the report."""
    report_path = '/home/user/final_report.md'
    with open(report_path, 'r') as f:
        report_content = f.read()

    # Find all code headers
    headers = re.findall(r'^## Code: (\d{3})$', report_content, re.MULTILINE)
    assert len(headers) > 0, "No code headers found in the report."

    # Check ascending order
    int_headers = [int(h) for h in headers]
    assert int_headers == sorted(int_headers), "Code sections are not sorted in ascending numerical order."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
