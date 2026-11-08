#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_order_txt_exists():
    path = "/home/user/order.txt"
    assert os.path.isfile(path), f"Expected output file {path} is missing. Did you write the execution order to this file?"

def test_order_txt_content():
    path = "/home/user/order.txt"
    assert os.path.isfile(path), f"Expected output file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_order = "E,D,B,C,A,F,G"

    # The tie-breaker rule specifies alphabetically smallest ID first when multiple nodes are available.
    # Let's trace the graph:
    # E has no deps -> E
    # D depends on E -> D
    # C depends on D, E
    # B depends on D
    # Available after D: B and C. B comes before C alphabetically. -> B
    # Available after B: C, G. C comes before G alphabetically. -> C
    # Available after C: A (depends on B, C), G. A comes before G alphabetically. -> A
    # Available after A: F (depends on A), G. F comes before G alphabetically. -> F
    # Available after F: G. -> G
    # Order: E, D, B, C, A, F, G

    assert content == expected_order, f"Incorrect execution order in {path}. Expected '{expected_order}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
