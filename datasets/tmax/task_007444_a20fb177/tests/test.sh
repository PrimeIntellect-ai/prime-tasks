#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math

def test_calibrated_norms_file_exists():
    """Check if the output file was created."""
    output_path = '/home/user/calibrated_norms.csv'
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"

def test_calibrated_norms_correctness():
    """Recompute the expected L2 norms from the source files and verify the output."""
    # 1. Read metadata
    metadata_path = '/home/user/sensor_metadata.csv'
    assert os.path.isfile(metadata_path), "Metadata file missing"

    metadata = {}
    with open(metadata_path, 'r', encoding='iso-8859-1') as f:
        reader = csv.DictReader(f)
        for row in reader:
            metadata[row['Sensor_ID']] = {
                'Cal_Multiplier': float(row['Cal_Multiplier']),
                'Offset': float(row['Offset'])
            }

    # 2. Read readings and compute norms
    readings_path = '/home/user/sensor_readings.csv'
    assert os.path.isfile(readings_path), "Readings file missing"

    l2_norms = {}
    with open(readings_path, 'r', encoding='utf-16le') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sid = row['Sensor_ID']
            if sid not in metadata:
                continue

            sq_sum = 0.0
            for col in ['t_0', 't_1', 't_2', 't_3', 't_4']:
                raw = float(row[col])
                calibrated = raw * metadata[sid]['Cal_Multiplier'] + metadata[sid]['Offset']
                sq_sum += calibrated ** 2

            l2_norms[sid] = math.sqrt(sq_sum)

    # 3. Sort expected values (descending L2 norm, then ascending Sensor_ID)
    # Format L2_Norm to 3 decimal places for strict comparison
    expected_list = sorted(
        [{'Sensor_ID': sid, 'L2_Norm': f"{norm:.3f}"} for sid, norm in l2_norms.items()],
        key=lambda x: (-float(x['L2_Norm']), x['Sensor_ID'])
    )

    # 4. Read and validate actual output
    output_path = '/home/user/calibrated_norms.csv'
    actual_list = []

    with open(output_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['Sensor_ID', 'L2_Norm'], f"Incorrect columns in output file: {header}"

        for row_idx, row in enumerate(reader, start=2):
            if not row:
                continue
            assert len(row) == 2, f"Row {row_idx} does not have exactly 2 columns: {row}"
            try:
                # Parse and re-format to ensure strict 3 decimal places
                actual_list.append({
                    'Sensor_ID': row[0].strip(),
                    'L2_Norm': f"{float(row[1].strip()):.3f}"
                })
            except ValueError:
                assert False, f"Invalid L2_Norm value in row {row_idx}: {row[1]}"

    # 5. Compare lengths and contents
    assert len(actual_list) == len(expected_list), \
        f"Expected {len(expected_list)} rows of data, but got {len(actual_list)}"

    for i, (actual, expected) in enumerate(zip(actual_list, expected_list)):
        assert actual['Sensor_ID'] == expected['Sensor_ID'], \
            f"Row {i+1}: Expected Sensor_ID '{expected['Sensor_ID']}', got '{actual['Sensor_ID']}'"
        assert actual['L2_Norm'] == expected['L2_Norm'], \
            f"Row {i+1} for Sensor {expected['Sensor_ID']}: Expected L2_Norm '{expected['L2_Norm']}', got '{actual['L2_Norm']}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
