#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_gzip_offsets():
    offsets_file = "/home/user/data/gzip_offsets.txt"
    assert os.path.isfile(offsets_file), f"File {offsets_file} does not exist."

    with open(offsets_file, "r") as f:
        content = f.read().strip()

    expected_offsets = ["100", "500", "1000", "2000"]
    actual_offsets = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_offsets == expected_offsets, (
        f"Contents of {offsets_file} are incorrect.\n"
        f"Expected: {expected_offsets}\n"
        f"Got: {actual_offsets}"
    )

def test_recovered_data():
    recovered_file = "/home/user/data/recovered_data.txt"
    assert os.path.isfile(recovered_file), f"File {recovered_file} does not exist."

    with open(recovered_file, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "System config ok.",
        "Database backup complete.",
        "User data intact."
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {recovered_file} are incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
