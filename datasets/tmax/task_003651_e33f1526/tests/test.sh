#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

REPORT_PATH = "/home/user/audit/compliance_report.txt"

def test_compliance_report_exists():
    """Test that the compliance report file exists."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

def test_compliance_report_format_and_schema():
    """Test the structure and schema of the compliance report."""
    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    assert "SCHEMA:" in content, "The report must contain the 'SCHEMA:' header."
    assert "VIOLATION PATH:" in content, "The report must contain the 'VIOLATION PATH:' header."

    # Extract schema fields
    schema_section = content.split("VIOLATION PATH:")[0].strip()
    field_lines = [line for line in schema_section.split('\n') if line.lower().startswith('field')]

    assert len(field_lines) == 5, "There should be exactly 5 fields defined in the schema."

    # Check field meanings approximately based on their order
    # Expected order: Source, Destination, Protocol, Port, Rule ID
    expected_keywords = [
        ['source', 'src'],
        ['destination', 'dest', 'target'],
        ['protocol', 'proto'],
        ['port'],
        ['rule', 'id']
    ]

    for i, line in enumerate(field_lines):
        line_lower = line.lower()
        matched = any(kw in line_lower for kw in expected_keywords[i])
        assert matched, f"Field {i+1} does not seem to match the expected logical name. Found: {line}"

def test_compliance_report_violation_path():
    """Test that the violation path is one of the correct shortest paths."""
    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    parts = content.split("VIOLATION PATH:")
    assert len(parts) >= 2, "Missing 'VIOLATION PATH:' section."

    path_section = parts[1].strip()
    path_lines = [line.strip() for line in path_section.split('\n') if line.strip()]

    assert len(path_lines) >= 1, "Violation path is missing below the header."

    actual_path = path_lines[0]

    valid_paths = [
        "SecurePaymentGateway -> BackendProcessor -> MetricsProxy -> MonitoringDash -> PublicInternet",
        "SecurePaymentGateway -> BackendProcessor -> InventoryDB -> LegacyAPI -> PublicInternet"
    ]

    assert actual_path in valid_paths, (
        f"The violation path is incorrect or not formatted properly.\n"
        f"Expected one of:\n{valid_paths[0]}\n{valid_paths[1]}\n"
        f"Got:\n{actual_path}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
