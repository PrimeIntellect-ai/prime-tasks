#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
from pathlib import Path

def test_sampled_data_output():
    """Test that sampled_data.csv exists and contains the correct sampled rows."""
    output_file = Path("/home/user/sampled_data.csv")
    assert output_file.exists(), f"Output file {output_file} is missing."
    assert output_file.is_file(), f"Path {output_file} is not a file."

    expected_content = (
        "timestamp,sensor_id,temperature,humidity\n"
        "2023-10-01T00:00:00Z,SENS-A,22.1,45\n"
        "2023-10-01T01:40:00Z,SENS-A,21.9,48\n"
        "2023-10-01T00:05:00Z,SENS-B,18.1,65\n"
        "2023-10-01T01:45:00Z,SENS-B,17.9,68\n"
    )

    with open(output_file, "r") as f:
        actual_content = f.read()

    # Standardize line endings for comparison
    actual_content = actual_content.strip().replace("\r\n", "\n") + "\n"

    assert actual_content == expected_content, (
        f"The content of {output_file} does not match the expected sampled data.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )

def test_invalid_data_moved():
    """Test that the corrupted file was moved to the invalid_data directory."""
    invalid_dir = Path("/home/user/invalid_data")
    assert invalid_dir.exists(), f"Directory {invalid_dir} was not created."
    assert invalid_dir.is_dir(), f"Path {invalid_dir} is not a directory."

    corrupt_file = invalid_dir / "corrupt.csv"
    assert corrupt_file.exists(), f"Corrupted file was not moved to {corrupt_file}."

    # Also verify it's no longer in the original directory
    orig_corrupt_file = Path("/home/user/sensor_data/corrupt.csv")
    assert not orig_corrupt_file.exists(), f"Corrupted file should be removed from {orig_corrupt_file}."

def test_deduplication():
    """Test that identical files in sensor_data were deduplicated."""
    sensor_data_dir = Path("/home/user/sensor_data")
    assert sensor_data_dir.exists(), f"Directory {sensor_data_dir} is missing."

    # We expect exactly one file with the content of sensor_A.csv
    sensor_a_content = (
        "timestamp,sensor_id,temperature,humidity\n"
        "2023-10-01T00:00:00Z,SENS-A,22.1,45\n"
        "2023-10-01T00:10:00Z,SENS-A,22.2,46\n"
        "2023-10-01T00:20:00Z,SENS-A,22.3,45\n"
        "2023-10-01T00:30:00Z,SENS-A,22.4,44\n"
        "2023-10-01T00:40:00Z,SENS-A,22.5,43\n"
        "2023-10-01T00:50:00Z,SENS-A,22.4,43\n"
        "2023-10-01T01:00:00Z,SENS-A,22.3,44\n"
        "2023-10-01T01:10:00Z,SENS-A,22.2,45\n"
        "2023-10-01T01:20:00Z,SENS-A,22.1,46\n"
        "2023-10-01T01:30:00Z,SENS-A,22.0,47\n"
        "2023-10-01T01:40:00Z,SENS-A,21.9,48\n"
        "2023-10-01T01:50:00Z,SENS-A,21.8,49\n"
        "2023-10-01T02:00:00Z,SENS-A,21.7,50\n"
        "2023-10-01T02:10:00Z,SENS-A,21.6,51\n"
        "2023-10-01T02:20:00Z,SENS-A,21.5,52\n"
    )

    target_hash = hashlib.md5(sensor_a_content.encode('utf-8')).hexdigest()

    matching_files = 0
    for file_path in sensor_data_dir.glob("*.csv"):
        if file_path.is_file():
            with open(file_path, "rb") as f:
                file_hash = hashlib.md5(f.read()).hexdigest()
                if file_hash == target_hash:
                    matching_files += 1

    assert matching_files == 1, (
        f"Expected exactly 1 file with the content of sensor_A in {sensor_data_dir}, "
        f"but found {matching_files}. Deduplication failed."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
