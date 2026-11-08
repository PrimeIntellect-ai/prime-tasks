#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def compute_expected_features(raw_data_path):
    expected = []
    with open(raw_data_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) != 3:
                continue
            primer = parts[0]
            target = parts[1]
            data = parts[2]

            # 1. Alignment score
            score = sum(1 for p, t in zip(primer, target) if p == t)

            # 2. Regression Slope
            pts = data.split(';')
            xs = []
            ys = []
            for pt in pts:
                x_str, y_str = pt.split(',')
                xs.append(float(x_str))
                ys.append(float(y_str))

            n = len(xs)
            sum_x = sum(xs)
            sum_y = sum(ys)
            sum_xy = sum(x * y for x, y in zip(xs, ys))
            sum_x2 = sum(x * x for x in xs)

            denominator = (n * sum_x2 - sum_x**2)
            if denominator == 0:
                m = 0.0
            else:
                m = (n * sum_xy - sum_x * sum_y) / denominator

            # Format to exactly 2 decimal places
            expected.append(f"{score},{m:.2f}")
    return expected

def test_features_csv_exists_and_correct():
    raw_data_path = "/home/user/raw_data.tsv"
    features_path = "/home/user/features.csv"

    assert os.path.exists(raw_data_path), f"Input file {raw_data_path} is missing."
    assert os.path.exists(features_path), f"Output file {features_path} was not created."

    expected_lines = compute_expected_features(raw_data_path)

    with open(features_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {features_path}, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch on line {i+1} of {features_path}.\n"
            f"Expected: '{expected}'\n"
            f"Actual:   '{actual}'"
        )

def test_cpp_source_code_exists():
    cpp_path = "/home/user/feature_extractor.cpp"
    assert os.path.exists(cpp_path), f"C++ source code {cpp_path} does not exist."
    assert os.path.isfile(cpp_path), f"{cpp_path} is not a file."
TEST_EOF

run_checks() {
    local binary="/tmp/feature_extractor_verifier_$$"

    # Preserve the original assertions against the submitted final state.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # The submitted source must be valid C++17 and must itself generate the output.
    g++ -std=c++17 /home/user/feature_extractor.cpp -o "$binary" || return 1
    rm -f /home/user/features.csv
    timeout 10s "$binary" || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise the compiled extractor on verifier-supplied data so fixed output
    # for the four image rows cannot pass.
    cat << 'DATA_EOF' > /home/user/raw_data.tsv
ACGTAC	ACGTTC	0.0,1.0;2.0,5.0;5.0,11.0
AAAA	TTTT	1.0,8.0;3.0,5.0;7.0,-1.0
GATTACA	GACTATA	2.0,4.0;4.0,4.0;9.0,4.0
CGCG	CGCG	-2.0,-5.0;1.0,1.0;4.0,7.0;8.0,15.0
DATA_EOF
    rm -f /home/user/features.csv
    timeout 10s "$binary" || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    rm -f "$binary"
    return 0
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
