#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_outliers_tsv_exists_and_correct():
    outliers_path = "/home/user/outliers.tsv"
    assert os.path.isfile(outliers_path), f"Output file {outliers_path} was not created."

    with open(outliers_path, "r") as f:
        lines = [line.strip('\n') for line in f if line.strip('\n')]

    assert len(lines) == 2, f"Expected exactly 2 anomalous chunks in {outliers_path}, found {len(lines)}."

    expected_line_1 = "3\tGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGAAAAAAAAAA\t0.3000"
    expected_line_2 = "5\tAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGGGGGGGGGG\t0.3000"

    assert lines[0] == expected_line_1, f"First outlier line mismatch. Expected: {repr(expected_line_1)}, Got: {repr(lines[0])}"
    assert lines[1] == expected_line_2, f"Second outlier line mismatch. Expected: {repr(expected_line_2)}, Got: {repr(lines[1])}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
