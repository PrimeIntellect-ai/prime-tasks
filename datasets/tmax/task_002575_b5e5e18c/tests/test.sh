#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

OUTPUT_FILE = "/home/user/normalized_customers.csv"

EXPECTED_OUTPUT = [
    "id,name,email,phone",
    "000004,RENÉ,rene@domain.net,555-222-3333",
    "000007,FRANÇOIS,fran@cois.fr,555-333-4444",
    "000008,MÜLLER,muller@test.org,555-987-6543",
    "000012,JOSÉ PÉREZ,jose@example.com,555-123-4567",
    "000099,ÁLVARO,alvaro@domain.net,555-111-2222",
    "000105,INVALID GUY,invalid@mail.com,INVALID"
]

def test_output_file_exists():
    """Check if the normalized output file exists."""
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."

def test_output_file_content():
    """Check if the output file contains the correctly normalized and sorted records in UTF-8."""
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} is missing."

    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"The file {OUTPUT_FILE} is not properly encoded in UTF-8.")

    lines = [line.strip() for line in content.strip().split("\n")]

    assert len(lines) > 0, f"The file {OUTPUT_FILE} is empty."
    assert lines[0] == EXPECTED_OUTPUT[0], f"The header is incorrect. Expected: '{EXPECTED_OUTPUT[0]}', Got: '{lines[0]}'"

    assert len(lines) == len(EXPECTED_OUTPUT), f"Expected {len(EXPECTED_OUTPUT)} lines, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_OUTPUT)):
        assert actual == expected, f"Line {i+1} does not match.\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
