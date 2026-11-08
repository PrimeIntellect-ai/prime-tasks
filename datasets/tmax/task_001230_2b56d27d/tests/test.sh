#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math

def test_topics_csv_exists_and_format():
    """Check if the topics.csv file exists and has the correct format and values."""
    file_path = "/home/user/topics.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    expected_data = {
        101: (1.4429, -0.6977),
        102: (-2.0366, -0.6385),
        103: (1.3850, -0.6074),
        104: (-1.3196, 0.3060),
        105: (1.2166, -0.3853),
        106: (-1.7370, 1.0776),
        107: (1.8016, -0.3294),
        108: (-0.7529, 1.2747)
    }

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            assert False, f"The file {file_path} is empty."

        assert headers == ['ticket_id', 'pc1', 'pc2'], \
            f"Expected headers ['ticket_id', 'pc1', 'pc2'], but got {headers}"

        rows = list(reader)
        assert len(rows) == len(expected_data), \
            f"Expected {len(expected_data)} rows, but got {len(rows)}"

        # Check sorting by ticket_id
        ticket_ids = []
        for row in rows:
            assert len(row) == 3, f"Expected 3 columns per row, but got {len(row)} in row: {row}"
            try:
                ticket_id = int(row[0])
                pc1 = float(row[1])
                pc2 = float(row[2])
            except ValueError:
                assert False, f"Could not parse numeric values from row: {row}"

            ticket_ids.append(ticket_id)
            assert ticket_id in expected_data, f"Unexpected ticket_id {ticket_id} found."

            expected_pc1, expected_pc2 = expected_data[ticket_id]

            # Allow small floating point variations due to string representation or minor PCA differences
            assert math.isclose(pc1, expected_pc1, abs_tol=1e-3), \
                f"For ticket_id {ticket_id}, expected pc1 ~ {expected_pc1}, got {pc1}"
            assert math.isclose(pc2, expected_pc2, abs_tol=1e-3), \
                f"For ticket_id {ticket_id}, expected pc2 ~ {expected_pc2}, got {pc2}"

        # Ensure every expected ticket occurs exactly once and rows are sorted ascending.
        assert ticket_ids == sorted(expected_data), \
            f"Expected each ticket_id exactly once in ascending order, but got {ticket_ids}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
