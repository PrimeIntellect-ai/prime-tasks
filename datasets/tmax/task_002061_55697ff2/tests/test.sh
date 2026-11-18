#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_etl_output_exists_and_valid():
    output_path = "/home/user/etl_output.json"
    assert os.path.exists(output_path), f"The file {output_path} is missing. Did the script run successfully?"
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} does not contain valid JSON.")

    assert "total_deduplicated" in data, "Key 'total_deduplicated' missing from JSON output."
    assert data["total_deduplicated"] == 17, f"Expected total_deduplicated to be 17, got {data['total_deduplicated']}."

    assert "anomalous_hours" in data, "Key 'anomalous_hours' missing from JSON output."
    assert isinstance(data["anomalous_hours"], list), "'anomalous_hours' should be a list."
    assert data["anomalous_hours"] == ["2023-10-01T12:00:00Z"], f"Expected anomalous_hours to be ['2023-10-01T12:00:00Z'], got {data['anomalous_hours']}."

def test_no_temp_files_left():
    # Ensure no temporary files (.tmp, .temp) are left in /home/user
    for root, dirs, files in os.walk("/home/user"):
        for file in files:
            assert not file.endswith(".tmp"), f"Temporary file found outside /tmp: {os.path.join(root, file)}"
            assert not file.endswith(".temp"), f"Temporary file found outside /tmp: {os.path.join(root, file)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
