#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_final_state_json():
    backup_file = '/home/user/backup_data.json'
    final_file = '/home/user/final_state.json'

    assert os.path.exists(backup_file), f"Backup file {backup_file} is missing."
    assert os.path.exists(final_file), f"Final state file {final_file} was not created."

    with open(backup_file, 'r') as f:
        backup_data = json.load(f)

    expected_state = {
        "users": {},
        "interfaces": backup_data.get("interfaces", {}),
        "routes": {}
    }

    for user in backup_data.get("users", []):
        expected_state["users"][user["username"]] = user["group"]

    for route in backup_data.get("routes", []):
        expected_state["routes"][route["dest"]] = route["gw"]

    with open(final_file, 'r') as f:
        try:
            final_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Final state file {final_file} is not valid JSON.")

    assert final_data == expected_state, f"Final state in {final_file} does not match expected state."

def test_router_state_saved():
    state_file = '/home/user/.router_state'
    backup_file = '/home/user/backup_data.json'

    assert os.path.exists(state_file), f"Router state file {state_file} was not saved (did the script exit cleanly?)."

    with open(backup_file, 'r') as f:
        backup_data = json.load(f)

    expected_state = {
        "users": {},
        "interfaces": backup_data.get("interfaces", {}),
        "routes": {}
    }

    for user in backup_data.get("users", []):
        expected_state["users"][user["username"]] = user["group"]

    for route in backup_data.get("routes", []):
        expected_state["routes"][route["dest"]] = route["gw"]

    with open(state_file, 'r') as f:
        try:
            saved_state = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Router state file {state_file} is not valid JSON.")

    assert saved_state == expected_state, f"Saved state in {state_file} does not match expected state."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
