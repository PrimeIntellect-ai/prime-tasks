#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def levenshtein_distance(s1: str, s2: str) -> int:
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def test_timeline_exists_and_similarity():
    timeline_path = '/home/user/timeline.txt'
    assert os.path.exists(timeline_path), f"File {timeline_path} does not exist."
    assert os.path.isfile(timeline_path), f"{timeline_path} is not a file."

    with open(timeline_path, 'r') as f:
        pred = f.read().strip()

    truth = """1697152452 sshd[10102]: Failed password for invalid user root from 203.0.113.42 port 33333 ssh2
1697152455 sshd[10102]: Connection closed by invalid user root 203.0.113.42 port 33333 [preauth]
1697152501 203.0.113.42 - - \"GET /phpmyadmin HTTP/1.1\" 404 134 \"-\" \"curl/7.68.0\"
1697152505 203.0.113.42 - - \"POST /login HTTP/1.1\" 200 512 \"-\" \"curl/7.68.0\"
1697152510 kernel: [ 1234.5678] Firewall block: IN=eth0 OUT= MAC=... SRC=203.0.113.42 DST=..."""

    dist = levenshtein_distance(pred, truth)
    max_len = max(len(pred), len(truth))
    sim = 1.0 - (dist / max_len) if max_len > 0 else 0.0

    assert sim >= 0.85, f"Normalized Levenshtein similarity is {sim:.4f}, which is below the threshold of 0.85."
    assert pred == truth, "Timeline does not exactly match the required normalized, chronological entries."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
