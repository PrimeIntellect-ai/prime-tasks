#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_combined_high_quality_csv():
    output_file = "/home/user/combined_high_quality.csv"

    # 1. Check if the file exists
    assert os.path.isfile(output_file), f"The file {output_file} does not exist. Did you create it?"

    # Read the contents
    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    # 2. Check if the file is empty
    assert len(lines) > 0, f"The file {output_file} is empty."

    # 3. Check the header
    header = lines[0]
    expected_header = "timestamp,value"
    assert header == expected_header, f"Expected header '{expected_header}', but got '{header}'."

    # 4. Check the data rows
    data_rows = lines[1:]
    expected_data_rows = [
        "1700000001,43.1",
        "1700000002,43.2",
        "1700000010,42.5",
        "1700000011,42.6"
    ]

    assert len(data_rows) == len(expected_data_rows), (
        f"Expected {len(expected_data_rows)} data rows, but got {len(data_rows)}. "
        "Did you filter only the 'high' quality runs?"
    )

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data_rows)):
        assert actual == expected, (
            f"Row {i+1} mismatch. Expected '{expected}', but got '{actual}'. "
            "Ensure you are sorting numerically by timestamp."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
