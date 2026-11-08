#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_fast_mcmc_exists_and_executable():
    path = "/home/user/fast_mcmc.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

def test_fast_mcmc_no_forbidden_tools():
    path = "/home/user/fast_mcmc.sh"
    with open(path, "r") as f:
        content = f.read()

    # We check that bc, awk, python are not used (at least as simple commands)
    for tool in ["bc", "awk", "python"]:
        assert tool not in content, f"Forbidden tool '{tool}' found in {path}. You must use pure Bash integer arithmetic."

def test_result_is_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you redirect the output?"

    # Compute the expected result
    seq_path = "/home/user/seq.fasta"
    assert os.path.isfile(seq_path), f"File {seq_path} is missing."

    seq = ""
    with open(seq_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(">"):
                seq += line

    L = len(seq)
    GC = seq.count("G") + seq.count("C")

    randoms_path = "/home/user/randoms.txt"
    assert os.path.isfile(randoms_path), f"File {randoms_path} is missing."

    X = 0
    with open(randoms_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            R = int(line)
            if R * L < GC * 32767:
                X += 1
            else:
                X -= 1

    with open(result_path, "r") as f:
        result_str = f.read().strip()

    assert result_str.lstrip("-").isdigit(), f"Result in {result_path} is not a valid integer: '{result_str}'"
    assert int(result_str) == X, f"Result in {result_path} is {result_str}, but expected {X}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
