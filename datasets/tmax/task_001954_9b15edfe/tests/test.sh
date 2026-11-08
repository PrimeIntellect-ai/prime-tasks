#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

FIREWALL_SCRIPT_PATH = "/home/user/apply_firewall.sh"

def test_firewall_script_exists_and_executable():
    """Test that the firewall script exists and is executable."""
    assert os.path.exists(FIREWALL_SCRIPT_PATH), f"The file {FIREWALL_SCRIPT_PATH} does not exist."
    assert os.path.isfile(FIREWALL_SCRIPT_PATH), f"{FIREWALL_SCRIPT_PATH} is not a regular file."
    assert os.access(FIREWALL_SCRIPT_PATH, os.X_OK), f"{FIREWALL_SCRIPT_PATH} does not have execute permissions."

def test_firewall_script_content():
    """Test that the firewall script contains the correct iptables commands sorted by IP."""
    expected_content = (
        "#!/bin/bash\n"
        "iptables -A OUTPUT -d 10.2.3.4 -j DROP\n"
        "iptables -A OUTPUT -d 10.55.1.9 -j DROP\n"
        "iptables -A OUTPUT -d 172.16.0.50 -j DROP\n"
    )

    assert os.path.exists(FIREWALL_SCRIPT_PATH), f"The file {FIREWALL_SCRIPT_PATH} does not exist."

    with open(FIREWALL_SCRIPT_PATH, "r") as f:
        actual_content = f.read()

    # Normalize line endings and trailing whitespace for robust comparison
    actual_lines = [line.strip() for line in actual_content.strip().split('\n')]
    expected_lines = [line.strip() for line in expected_content.strip().split('\n')]

    assert actual_lines == expected_lines, (
        f"The content of {FIREWALL_SCRIPT_PATH} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
