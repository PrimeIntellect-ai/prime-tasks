#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_data_exists_and_content():
    clean_data_path = "/home/user/clean_data.csv"

    # Check if file exists
    assert os.path.isfile(clean_data_path), f"The file {clean_data_path} is missing. Did you save the output to the correct location?"

    # Expected content based on the task description
    expected_content = """timestamp,sensor_name,value,rolling_avg
1000,sensor1,10.0,10.00
1001,sensor1,13.0,11.50
1002,sensor1,11.0,11.33
1003,sensor1,32.0,18.67
1004,sensor1,15.0,19.33
1000,sensor2,20.0,20.00
1001,sensor2,21.0,20.50
1002,sensor2,25.0,22.00
1003,sensor2,19.0,21.67
1004,sensor2,20.0,21.33"""

    with open(clean_data_path, "r") as f:
        actual_content = f.read().strip()

    # Compare actual vs expected
    assert actual_content == expected_content.strip(), (
        f"The content of {clean_data_path} does not match the expected final state.\n"
        "Ensure you have deduplicated correctly, reshaped to long format, "
        "calculated the 3-period simple moving average correctly, and sorted the output."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
