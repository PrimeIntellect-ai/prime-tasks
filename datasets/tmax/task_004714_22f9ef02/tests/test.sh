#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_final_hashes():
    """
    Validates that the output file exists, contains the correct SHA-256 hashes
    with a Jaccard similarity >= 0.85 compared to the ground truth, and is sorted.
    """
    output_path = '/home/user/unique_alert_hashes.txt'
    assert os.path.exists(output_path), f"Output file {output_path} not found."

    # Ground truth codes derived from the audio and binary log
    expected_codes = {"DBA-1100", "ERR-9910", "NET-4431", "SEC-8812", "SYS-0042"}
    expected_hashes = set(hashlib.sha256(c.encode('utf-8')).hexdigest() for c in expected_codes)

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    agent_hashes = set(lines)

    # Calculate Jaccard similarity
    intersection = len(expected_hashes.intersection(agent_hashes))
    union = len(expected_hashes.union(agent_hashes))

    jaccard = intersection / union if union > 0 else 0.0

    assert jaccard >= 0.85, f"Jaccard similarity {jaccard:.2f} is below the threshold of 0.85. Expected hashes: {expected_hashes}"

    # Check if the hashes are sorted alphabetically as requested
    assert lines == sorted(lines), "The hashes in the output file are not sorted in alphabetical order."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
