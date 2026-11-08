#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat

def test_firewall_rules_exist_and_permissions():
    script_path = "/home/user/firewall_rules.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    st = os.stat(script_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o700, f"Expected permissions 0o700, got {oct(permissions)}"

def test_firewall_rules_content():
    script_path = "/home/user/firewall_rules.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "iptables -A INPUT -s 192.168.1.50 -j DROP",
        "iptables -A INPUT -s 10.0.5.12 -j DROP",
        "iptables -A INPUT -s 172.16.20.100 -j DROP"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"Expected firewall rules {expected_lines}, but got {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
