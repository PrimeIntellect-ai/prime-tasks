#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_diverging_txt_exists_and_correct():
    fasta_path = "/home/user/sequences.fasta"
    output_path = "/home/user/diverging.txt"

    assert os.path.exists(fasta_path), f"Input file {fasta_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} was not created."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    # Parse FASTA and compute expected diverging sequences
    expected_diverging = []
    with open(fasta_path, "r") as f:
        current_id = None
        current_seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    seq_str = "".join(current_seq).upper()
                    gc_count = seq_str.count('G') + seq_str.count('C')
                    if len(seq_str) > 0 and (gc_count / len(seq_str)) > 0.8:
                        expected_diverging.append(current_id)
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)

        # Process the last sequence
        if current_id is not None:
            seq_str = "".join(current_seq).upper()
            gc_count = seq_str.count('G') + seq_str.count('C')
            if len(seq_str) > 0 and (gc_count / len(seq_str)) > 0.8:
                expected_diverging.append(current_id)

    expected_diverging.sort()

    with open(output_path, "r") as f:
        actual_content = [line.strip() for line in f if line.strip()]

    assert actual_content == expected_diverging, (
        f"Contents of {output_path} do not match the expected diverging sequence IDs. "
        f"Expected: {expected_diverging}, Actual: {actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
