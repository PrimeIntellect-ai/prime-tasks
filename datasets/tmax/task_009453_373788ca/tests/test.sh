#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
from collections import defaultdict

def test_top_cited_file_exists():
    output_file = "/home/user/top_cited.txt"
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

def test_top_cited_correctness():
    data_file = "/home/user/citation_graph/data/papers.jsonl"
    assert os.path.isfile(data_file), f"Dataset file {data_file} is missing."

    in_degrees = defaultdict(int)

    with open(data_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            paper = json.loads(line)
            for ref in paper.get("references", []):
                in_degrees[ref] += 1

    if not in_degrees:
        expected_top_cited = ""
    else:
        # Find the max in-degree paper
        expected_top_cited = max(in_degrees.items(), key=lambda x: x[1])[0]

    output_file = "/home/user/top_cited.txt"
    with open(output_file, 'r') as f:
        actual_top_cited = f.read().strip()

    assert actual_top_cited == expected_top_cited, (
        f"Incorrect top cited paper ID. "
        f"Expected '{expected_top_cited}', but got '{actual_top_cited}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
