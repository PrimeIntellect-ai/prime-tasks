#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def generate_expected_output():
    """Derive the expected RLE lines based on the setup script logic."""
    expected_lines = []
    for txid in range(1, 51):
        if txid % 3 == 0:
            char1 = chr(65 + (txid % 26))
            char2 = chr(65 + ((txid + 1) % 26))
            count1 = txid
            count2 = txid + 2

            # The payload is char1 * count1 + char2 * count2
            # RLE compression of this is simply count1 + char1 + count2 + char2
            rle_string = f"{count1}{char1}{count2}{char2}"
            expected_lines.append(rle_string)

    return expected_lines

def test_archive_rle_exists_and_correct():
    archive_path = '/home/user/archive.rle'
    assert os.path.isfile(archive_path), f"Output file {archive_path} does not exist."

    with open(archive_path, 'r', encoding='ascii') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]
    expected_lines = generate_expected_output()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {archive_path}, but got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
