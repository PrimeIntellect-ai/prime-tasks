#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import math
import os

def test_corr_result_exists_and_correct():
    result_path = '/home/user/corr_result.txt'
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you redirect the output of your program?"

    # Recompute the expected ground truth correlation
    N = 1000
    emb1 = [float(i) for i in range(N)]
    emb2 = [float(i * i) for i in range(N)]

    mean1 = sum(emb1) / N
    mean2 = sum(emb2) / N

    num = sum((x - mean1) * (y - mean2) for x, y in zip(emb1, emb2))
    den = math.sqrt(sum((x - mean1)**2 for x in emb1) * sum((y - mean2)**2 for y in emb2))
    expected_corr = num / den
    expected_str = f"{expected_corr:.4f}"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_str, f"Expected correlation {expected_str}, but got '{content}' in {result_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
