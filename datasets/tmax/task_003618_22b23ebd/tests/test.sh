#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_restore_plan_exists():
    """Verify that the restore_plan.json file was created."""
    file_path = '/home/user/restore_plan.json'
    assert os.path.isfile(file_path), f"The output file {file_path} was not created."

def test_restore_plan_content():
    """Verify that the restore plan contains the correct sequence of backup files."""
    file_path = '/home/user/restore_plan.json'

    with open(file_path, 'r') as f:
        try:
            plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    expected_plan = ["s3://backups/f1.tar", "s3://backups/d1.diff", "s3://backups/i3.inc"]

    assert isinstance(plan, list), f"Expected the restore plan to be a JSON array (list), got {type(plan).__name__}."
    assert plan == expected_plan, f"The restore plan is incorrect. Expected {expected_plan}, but got {plan}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
