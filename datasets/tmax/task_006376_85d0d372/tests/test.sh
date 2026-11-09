#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_processed_fleet_exists():
    """Test that the processed fleet data CSV file exists."""
    file_path = '/home/user/processed_fleet.csv'
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

def test_processed_fleet_content():
    """Test that the processed fleet data CSV file has the correct final content."""
    file_path = '/home/user/processed_fleet.csv'
    expected_content = """timestamp,vehicle_id,speed,temp,rolling_speed_avg
2023-01-01T10:10:00,V1,55,25,50.00
2023-01-01T10:20:00,V1,60,26,51.67
2023-01-01T10:10:00,V2,65,22,60.00
2023-01-01T10:15:00,V2,70,23,63.33"""

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {file_path} does not match the expected final state."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
