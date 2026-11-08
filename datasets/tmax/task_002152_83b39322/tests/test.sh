#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_anomalies_file_exists():
    assert os.path.isfile('/home/user/data_prep/anomalies.txt'), "The file /home/user/data_prep/anomalies.txt was not created."

def test_anomalies_content_correct():
    raw_path = '/home/user/data_prep/raw_data.csv'
    ref_path = '/home/user/data_prep/reference.csv'
    anomalies_path = '/home/user/data_prep/anomalies.txt'

    assert os.path.isfile(raw_path), f"Missing {raw_path}"
    assert os.path.isfile(ref_path), f"Missing {ref_path}"
    assert os.path.isfile(anomalies_path), f"Missing {anomalies_path}"

    # Read reference data
    ref_data = {}
    with open(ref_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ref_data[int(row['id'])] = float(row['x'])

    # Compute expected anomalies
    expected_anomalies = []
    with open(raw_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_id = int(row['id'])
            y = float(row['y'])
            a = float(row['a'])
            b = float(row['b'])

            calculated_x = (y - b) / a

            if row_id not in ref_data:
                expected_anomalies.append(row_id)
            else:
                ref_x = ref_data[row_id]
                if abs(calculated_x - ref_x) > 0.01:
                    expected_anomalies.append(row_id)

    expected_anomalies.sort()

    # Read actual anomalies
    actual_anomalies = []
    with open(anomalies_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual_anomalies.append(int(line))
                except ValueError:
                    assert False, f"Found non-integer value in anomalies.txt: '{line}'"

    # Compare
    assert actual_anomalies == expected_anomalies, (
        f"The anomalies in {anomalies_path} do not match the expected anomalies. "
        f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
