#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
from collections import Counter

def test_summary_json_exists_and_correct():
    summary_path = '/home/user/summary.json'
    log_path = '/home/user/access_logs.jsonl'

    assert os.path.exists(summary_path), f"The output file {summary_path} does not exist."
    assert os.path.isfile(summary_path), f"The path {summary_path} is not a file."
    assert os.path.exists(log_path), f"The input file {log_path} is missing."

    # Recompute the expected values directly from the source file
    expected_valid_lines = 0
    expected_invalid_lines = 0
    ip_counter = Counter()

    with open(log_path, 'r', encoding='utf-8') as f:
        for line in f:
            try:
                data = json.loads(line)
                if isinstance(data, dict) and "ip" in data:
                    expected_valid_lines += 1
                    ip_counter[data["ip"]] += 1
                else:
                    expected_invalid_lines += 1
            except json.JSONDecodeError:
                expected_invalid_lines += 1

    # Sort by frequency (descending) and then by IP (ascending)
    sorted_ips = sorted(ip_counter.items(), key=lambda x: (-x[1], x[0]))
    expected_top_ips = [ip for ip, count in sorted_ips[:3]]

    # Load the student's output
    with open(summary_path, 'r', encoding='utf-8') as f:
        try:
            summary_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {summary_path} does not contain valid JSON."

    assert isinstance(summary_data, dict), f"The root of {summary_path} must be a JSON object."

    # Validate the counts and top IPs
    assert "valid_lines" in summary_data, "The key 'valid_lines' is missing from the summary."
    assert summary_data["valid_lines"] == expected_valid_lines, \
        f"Expected {expected_valid_lines} valid lines, but got {summary_data['valid_lines']}."

    assert "invalid_lines" in summary_data, "The key 'invalid_lines' is missing from the summary."
    assert summary_data["invalid_lines"] == expected_invalid_lines, \
        f"Expected {expected_invalid_lines} invalid lines, but got {summary_data['invalid_lines']}."

    assert "top_ips" in summary_data, "The key 'top_ips' is missing from the summary."
    assert summary_data["top_ips"] == expected_top_ips, \
        f"Expected top_ips to be {expected_top_ips}, but got {summary_data['top_ips']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
