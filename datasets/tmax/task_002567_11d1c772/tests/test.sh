#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_registry_index_csv():
    file_path = "/home/user/registry_index.csv"
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."

    with open(file_path, "r", newline="") as f:
        content = f.read()

    lines = [line.strip() for line in content.strip().split("\n")]

    assert len(lines) == 6, f"Expected 6 lines in CSV (1 header + 5 rows), got {len(lines)}"
    assert lines[0] == "id,version,size", f"Header is incorrect: {lines[0]}"

    expected_lines = [
        "pkg-delta-42,4.2.0,9999999",
        "bin-alpha-01,1.0.0,1048576",
        "bin-epsilon,1.0.1,1048576",
        "bin-beta-99,2.1.4-rc1,512000",
        "lib-gamma-zz,0.9.9,2048"
    ]

    for i, expected in enumerate(expected_lines):
        assert lines[i+1] == expected, f"Line {i+2} is incorrect. Expected '{expected}', got '{lines[i+1]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
