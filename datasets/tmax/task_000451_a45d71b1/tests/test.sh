#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import subprocess
import pytest

def test_csv_format_and_rows():
    """Check that the output CSV exists and has the correct format and number of rows."""
    output_csv = "/home/user/vulnerable_systems.csv"
    assert os.path.exists(output_csv), f"Output file not found: {output_csv}"

    with open(output_csv, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "CSV file is empty"
        assert len(header) == 2, f"Expected 2 columns, found {len(header)} in header"
        assert header[0] == "system_id" and header[1] == "vulnerability_score", f"Unexpected header: {header}"

        rows = list(reader)
        assert len(rows) == 50, f"Expected exactly 50 data rows, found {len(rows)}"
        for i, row in enumerate(rows):
            assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns: {row}"

def test_iou_metric():
    """Run the verifier script to calculate IoU and assert it meets the threshold."""
    output_csv = "/home/user/vulnerable_systems.csv"
    assert os.path.exists(output_csv), f"Output file not found: {output_csv}"

    verifier_script = "/tests/verifier.py"
    assert os.path.exists(verifier_script), f"Verifier script not found: {verifier_script}"

    result = subprocess.run(["python3", verifier_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Verifier script failed with error: {result.stderr}"

    output_str = result.stdout.strip()
    try:
        iou = float(output_str)
    except ValueError:
        pytest.fail(f"Verifier script did not output a valid float. Output: {output_str}")

    threshold = 0.90
    assert iou >= threshold, f"IoU metric failed: measured {iou:.4f}, expected >= {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
