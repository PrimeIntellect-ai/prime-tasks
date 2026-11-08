#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_bottlenecks_file():
    """Verify that the bottlenecks.txt file exists and contains the correct top 3 employees."""
    file_path = "/home/user/bottlenecks.txt"

    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 names in {file_path}, but got {len(lines)}."

    valid_outputs = [
        ["Bob", "Charlie", "Eve"],
        ["Charlie", "Bob", "Eve"]
    ]

    assert lines in valid_outputs, (
        f"The contents of {file_path} are incorrect.\n"
        f"Expected either ['Bob', 'Charlie', 'Eve'] or ['Charlie', 'Bob', 'Eve'].\n"
        f"Got: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
