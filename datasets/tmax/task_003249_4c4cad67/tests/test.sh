#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def test_tvd_result():
    file1 = "/home/user/run1_gc.tsv"
    file2 = "/home/user/run2_gc.tsv"
    out_file = "/home/user/tvd_result.txt"

    assert os.path.exists(file1), f"Input file {file1} is missing."
    assert os.path.exists(file2), f"Input file {file2} is missing."
    assert os.path.exists(out_file), f"Output file {out_file} was not created."

    with open(file1, 'r') as f1, open(file2, 'r') as f2:
        lines1 = f1.read().strip().split('\n')[1:]
        lines2 = f2.read().strip().split('\n')[1:]

    data1 = [tuple(map(float, line.split('\t'))) for line in lines1 if line.strip()]
    data2 = [tuple(map(float, line.split('\t'))) for line in lines2 if line.strip()]

    assert len(data1) == len(data2), "Input files have different number of data points."

    integral = 0.0
    for i in range(len(data1) - 1):
        x_i, y1_i = data1[i]
        x_next, y1_next = data1[i+1]
        _, y2_i = data2[i]
        _, y2_next = data2[i+1]

        f_i = abs(y1_i - y2_i)
        f_next = abs(y1_next - y2_next)

        integral += (f_next + f_i) / 2.0 * (x_next - x_i)

    expected_tvd = integral * 0.5
    expected_str = f"{expected_tvd:.4f}"

    with open(out_file, 'r') as f:
        student_val = f.read().strip()

    assert student_val == expected_str, f"Expected TVD to be {expected_str}, but got {student_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
