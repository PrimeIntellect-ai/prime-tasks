#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import pytest

SCRIPT_PATH = "/home/user/firewall_block.sh"

def test_firewall_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

def test_firewall_script_executable():
    st = os.stat(SCRIPT_PATH)
    is_executable = bool(st.st_mode & stat.S_IXUSR)
    assert is_executable, f"The script {SCRIPT_PATH} does not have executable permissions."

def test_firewall_script_content():
    expected_lines = [
        "#!/bin/bash",
        "iptables -A INPUT -s 10.0.0.12 -j DROP",
        "iptables -A INPUT -s 172.16.5.100 -j DROP",
        "iptables -A INPUT -s 192.168.1.105 -j DROP",
        "iptables -A INPUT -s 192.168.1.50 -j DROP"
    ]

    with open(SCRIPT_PATH, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {SCRIPT_PATH} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
