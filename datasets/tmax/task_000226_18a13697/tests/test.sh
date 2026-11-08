#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os


def test_significant_count_file_exists():
    """Test that the significant_count.txt file exists."""
    file_path = "/home/user/significant_count.txt"
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."


def test_significant_count_value():
    """Test that significant_count.txt contains the count derived from the input."""
    output_path = "/home/user/significant_count.txt"
    sequences_path = "/home/user/sequences.txt"

    assert os.path.exists(output_path), f"The output file {output_path} is missing."
    assert os.path.exists(sequences_path), f"The input file {sequences_path} is missing."

    with open(output_path, "r") as f:
        student_output = f.read().strip()

    log_at = math.log(0.30 / 0.25)
    log_cg = math.log(0.20 / 0.25)
    expected_count = 0
    with open(sequences_path, "r") as f:
        for line in f:
            sequence = line.strip()
            at_count = sequence.count("A") + sequence.count("T")
            cg_count = sequence.count("C") + sequence.count("G")
            llr = at_count * log_at + cg_count * log_cg
            if llr > 5.0:
                expected_count += 1

    expected_output = str(expected_count)
    assert student_output == expected_output, (
        f"The count in {output_path} is incorrect. "
        f"Expected '{expected_output}', but got '{student_output}'."
    )


def test_cpp_source_file_exists():
    """Test that the C++ source file exists."""
    file_path = "/home/user/calc_llr.cpp"
    assert os.path.exists(file_path), f"The source file {file_path} is missing. Did you write the C++ code?"
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
