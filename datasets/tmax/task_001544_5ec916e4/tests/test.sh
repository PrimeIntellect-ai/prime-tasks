#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_gc_gradient_max():
    fasta_path = '/home/user/dna_sequence.fasta'
    output_path = '/home/user/gc_gradient_max.txt'

    assert os.path.exists(fasta_path), f"FASTA file missing at {fasta_path}"
    assert os.path.exists(output_path), f"Output file missing at {output_path}"

    # Read sequence
    with open(fasta_path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 1, "FASTA file is empty or missing sequence lines"
    assert lines[0].startswith(">"), "FASTA file missing header"

    seq = "".join(lines[1:])

    # Calculate expected windows
    windows = []
    for i in range(0, len(seq) - 100 + 1, 50):
        w = seq[i:i+100]
        gc = w.count('G') + w.count('C')
        windows.append(gc)

    # Calculate differences
    diffs = [abs(windows[i+1] - windows[i]) for i in range(len(windows)-1)]

    max_val = max(diffs)
    max_idx = diffs.index(max_val)

    expected_output = f"Index: {max_idx}, MaxDiff: {max_val}"

    # Read actual output
    with open(output_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Output file content is incorrect.\n"
        f"Expected: '{expected_output}'\n"
        f"Got: '{actual_output}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
