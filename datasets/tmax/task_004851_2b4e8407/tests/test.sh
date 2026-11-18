#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_report_exists_and_correct():
    """Test that the report.txt file exists and contains the correct values."""
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist. Did you create it?"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {report_path}, got {len(lines)}."

    k_val = lines[0]
    p_val = lines[1]

    assert k_val == "29", f"Expected k=29 on the first line, got '{k_val}'."
    assert p_val == "1.0000", f"Expected p-value=1.0000 on the second line, got '{p_val}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
