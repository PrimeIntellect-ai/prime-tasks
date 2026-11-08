#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
from decimal import Decimal

def test_incident_report_correctness():
    """Verify the incident report exists and contains the correctly computed metrics."""
    report_path = "/home/user/incident_report.txt"
    traffic_path = "/home/user/incident/traffic_dump.txt"
    db_path = "/home/user/incident/db_queries.log"

    assert os.path.isfile(report_path), f"The report file {report_path} is missing."
    assert os.path.isfile(traffic_path), f"The input file {traffic_path} is missing."
    assert os.path.isfile(db_path), f"The input file {db_path} is missing."

    # Recompute the truth values from the source files
    packets = 0
    exact_sum = Decimal('0')

    with open(traffic_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith('{') and '"ACC-999"' in line:
                try:
                    payload = json.loads(line)
                    if payload.get("account_id") == "ACC-999":
                        packets += 1
                        # Use string conversion to avoid float precision loss during Decimal instantiation
                        exact_sum += Decimal(str(payload.get("amount", 0)))
                except json.JSONDecodeError:
                    continue

    queries = 0
    with open(db_path, "r") as f:
        for line in f:
            if "UPDATE balances" in line and "ACC-999" in line:
                queries += 1

    lost_updates = packets - queries

    expected_lines = [
        f"Total packets received for ACC-999: {packets}",
        f"Total queries executed for ACC-999: {queries}",
        f"Lost updates: {lost_updates}",
        f"Correct exact sum: {exact_sum}"
    ]

    # Read the actual report
    with open(report_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == 4, f"The report should contain exactly 4 non-empty lines, but found {len(actual_lines)}."

    for i, expected_line in enumerate(expected_lines):
        assert actual_lines[i] == expected_line, (
            f"Report line {i+1} is incorrect.\n"
            f"Expected: '{expected_line}'\n"
            f"Found:    '{actual_lines[i]}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
