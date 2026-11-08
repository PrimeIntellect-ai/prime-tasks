#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_output_file_exists():
    output_path = '/home/user/output/spectral_distances.csv'
    assert os.path.isfile(output_path), f"The file {output_path} does not exist."

def test_output_file_content():
    output_path = '/home/user/output/spectral_distances.csv'
    assert os.path.isfile(output_path), f"The file {output_path} does not exist."

    expected_data = {
        'Seq_Reference': 0.000000,
        'Seq_Mutant_1': 0.000570,
        'Seq_Poly_G': 0.031250,
        'Seq_Poly_T': 0.031250,
        'Seq_Random': 0.027346
    }

    with open(output_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['Sequence_ID', 'Wasserstein_Distance'], f"Unexpected header: {header}"

        parsed_data = {}
        for row in reader:
            assert len(row) == 2, f"Row does not have exactly 2 columns: {row}"
            seq_id, dist_str = row
            try:
                dist = float(dist_str)
            except ValueError:
                pytest.fail(f"Distance value '{dist_str}' for {seq_id} is not a valid float.")
            parsed_data[seq_id] = dist

    assert len(parsed_data) == len(expected_data), f"Expected {len(expected_data)} rows, found {len(parsed_data)}"

    for seq_id, expected_dist in expected_data.items():
        assert seq_id in parsed_data, f"Sequence ID '{seq_id}' missing from output."
        actual_dist = parsed_data[seq_id]
        assert abs(actual_dist - expected_dist) <= 1e-5, f"Distance for {seq_id} is {actual_dist}, expected {expected_dist}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
