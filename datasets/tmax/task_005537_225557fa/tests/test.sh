#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
from itertools import combinations
import pytest

def encode_vlq(n):
    if n == 0:
        return [0]
    chunks = []
    while n > 0:
        chunks.append(n & 0x7F)
        n >>= 7
    chunks.reverse()
    for i in range(len(chunks) - 1):
        chunks[i] |= 0x80
    return chunks

def ref_encode(nums):
    if not nums: return ""
    deltas = [nums[0]]
    for i in range(1, len(nums)):
        deltas.append(nums[i] - nums[i-1])
    zigzags = [2*d if d >= 0 else -2*d - 1 for d in deltas]
    bytes_out = []
    for z in zigzags:
        bytes_out.extend(encode_vlq(z))
    return base64.b64encode(bytes(bytes_out)).decode('utf-8')

def buggy_encode(nums):
    if not nums: return ""
    deltas = [nums[0]]
    for i in range(1, len(nums)):
        deltas.append(nums[i] - nums[i-1])
    zigzags = []
    for d in deltas:
        if d == -5:
            zigzags.append(10)
        elif d >= 0:
            zigzags.append(2 * d)
        else:
            zigzags.append(-2 * d - 1)
    bytes_out = []
    for z in zigzags:
        bytes_out.extend(encode_vlq(z))
    return base64.b64encode(bytes(bytes_out)).decode('utf-8')

def get_expected_failures():
    valid_seqs = []
    for seq in combinations(range(-8, 9), 5):
        if sum(seq) == 4:
            valid_seqs.append(list(seq))

    failures = []
    for seq in valid_seqs:
        ref = ref_encode(seq)
        bug = buggy_encode(seq)
        if ref != bug:
            failures.append(f"{seq} | Expected: {ref} | Actual: {bug}")

    failures.sort()
    return failures

def test_failures_file_exists():
    assert os.path.exists("/home/user/failures.txt"), "The file /home/user/failures.txt does not exist."
    assert os.path.isfile("/home/user/failures.txt"), "/home/user/failures.txt is not a file."

def test_failures_file_content():
    expected_lines = get_expected_failures()

    with open("/home/user/failures.txt", "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} failures, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
