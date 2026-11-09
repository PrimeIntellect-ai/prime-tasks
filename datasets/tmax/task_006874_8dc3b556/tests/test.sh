#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_correlation_output():
    corr_path = '/home/user/correlation.txt'
    assert os.path.isfile(corr_path), f"File {corr_path} does not exist"

    with open(corr_path, 'r') as f:
        content = f.read().strip()

    assert content == "0.649", f"Expected correlation '0.649', but got '{content}'"

def test_inference_output():
    inference_path = '/home/user/inference_out.txt'
    assert os.path.isfile(inference_path), f"File {inference_path} does not exist"

    with open(inference_path, 'r') as f:
        content = f.read()

    expected_content = '{"posterior_mean": 0.812, "posterior_variance": 0.0042, "converged": true}\n'
    assert content == expected_content, "The inference output is incorrect or non-deterministic. Ensure environment variables were set correctly."

def test_reproducibility_hash():
    hash_path = '/home/user/reproducibility_hash.txt'
    assert os.path.isfile(hash_path), f"File {hash_path} does not exist"

    with open(hash_path, 'r') as f:
        content = f.read().strip()

    expected_hash = "66ccf2ebbcdd33db5afb452eec89e6eb"
    assert content == expected_hash, f"Expected MD5 hash '{expected_hash}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
