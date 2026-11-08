#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_compromised_actions_file_exists():
    path = "/home/user/audit/compromised_actions.txt"
    assert os.path.isfile(path), f"The file {path} does not exist. Did you generate the report?"

def test_compromised_actions_contents():
    path = "/home/user/audit/compromised_actions.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_actions = [
        "EXFILTRATE_USERS",
        "DELETE_ALL_AUDIT"
    ]

    actual_actions = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_actions == expected_actions, (
        f"The contents of {path} do not match the expected decrypted actions.\n"
        f"Expected: {expected_actions}\n"
        f"Got: {actual_actions}"
    )
TEST_EOF

run_checks() {
    test -f /home/user/audit_tool/Cargo.toml
    test -f /home/user/audit_tool/src/main.rs

    # Require the submitted Rust tool itself to create a fresh report.
    rm -f /home/user/audit/compromised_actions.txt
    cargo run --manifest-path /home/user/audit_tool/Cargo.toml

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
