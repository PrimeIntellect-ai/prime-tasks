#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_extracted_files_exist():
    """Verify that the evidence archive was extracted to /home/user/src/."""
    src_dir = "/home/user/src"
    assert os.path.exists(src_dir) and os.path.isdir(src_dir), f"Directory {src_dir} does not exist."

    expected_files = ["utils.rs", "auth.rs", "main.rs"]
    for f in expected_files:
        file_path = os.path.join(src_dir, f)
        assert os.path.exists(file_path), f"Expected extracted file {f} is missing in {src_dir}."

def test_audit_report_content():
    """Verify the content of the audit report."""
    report_path = "/home/user/audit_report.txt"
    assert os.path.exists(report_path), f"Audit report missing at {report_path}."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, found {len(lines)}."

    expected_line1 = "CWE-78: utils.rs:6"
    expected_line2 = "CWE-798: auth.rs:2"

    assert lines[0] == expected_line1, f"Expected first line to be '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Expected second line to be '{expected_line2}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
