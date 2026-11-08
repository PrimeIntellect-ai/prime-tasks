#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_storage_report_exists():
    """Check if the storage report file exists."""
    report_path = "/home/user/storage_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

def test_storage_report_content():
    """Check if the storage report contains the correct metrics."""
    report_path = "/home/user/storage_report.json"

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert "critical_error_count" in report_data, "Missing 'critical_error_count' key in report."
    assert "legacy_meta_ids" in report_data, "Missing 'legacy_meta_ids' key in report."
    assert "target_bin_count" in report_data, "Missing 'target_bin_count' key in report."

    # Check critical_error_count
    expected_critical_count = len([i for i in range(1, 101) if i % 7 == 0])
    assert report_data["critical_error_count"] == expected_critical_count, \
        f"Expected critical_error_count to be {expected_critical_count}, got {report_data['critical_error_count']}."

    # Check legacy_meta_ids
    expected_legacy_ids = sorted([f"META-{i:03d}" for i in range(1, 101) if i % 11 == 0])
    assert report_data["legacy_meta_ids"] == expected_legacy_ids, \
        f"Expected legacy_meta_ids to be {expected_legacy_ids}, got {report_data['legacy_meta_ids']}."

    # Check target_bin_count
    # Magic is 0xDEADC0DE if i % 5 == 0
    # Version is 3 if i % 2 == 0
    expected_bin_count = len([i for i in range(1, 101) if i % 5 == 0 and i % 2 == 0])
    assert report_data["target_bin_count"] == expected_bin_count, \
        f"Expected target_bin_count to be {expected_bin_count}, got {report_data['target_bin_count']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
