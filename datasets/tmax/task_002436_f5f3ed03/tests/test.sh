#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re


def derive_truth_from_log():
    seed = 31337
    ciphertexts = []

    with open('/app/access.log', 'r') as f:
        for line in f:
            match = re.search(
                r'GET /login\?next=http://evil-attacker\.net/[^ ]*?[?&]exfil_data=([0-9a-fA-F]+) HTTP/',
                line,
            )
            if match:
                ciphertexts.append(bytes.fromhex(match.group(1)))

    plaintexts = []
    for ciphertext in ciphertexts:
        state = seed
        plaintext = bytearray()
        for value in ciphertext:
            state = (1103515245 * state + 12345) % (2**31)
            plaintext.append(value ^ (state & 0xFF))
        plaintexts.append(plaintext.decode('utf-8'))

    return plaintexts


def test_recovered_cookies_accuracy():
    """
    Evaluate the accuracy of the recovered cookies against ground truth derived
    from the captured traffic. The accuracy must be >= 0.95 (95%).
    """
    agent_path = "/home/user/recovered_cookies.txt"

    assert os.path.exists(agent_path), f"Agent output file missing: {agent_path}"

    truth_lines = derive_truth_from_log()

    with open(agent_path, 'r') as f:
        agent_lines = [l.strip() for l in f.readlines() if l.strip()]

    assert len(truth_lines) > 0, "Ground truth is empty."

    correct = 0
    for t in truth_lines:
        if t in agent_lines:
            correct += 1

    accuracy = correct / len(truth_lines)

    assert accuracy >= 0.95, f"Recovered cookies accuracy {accuracy:.4f} is below the 0.95 threshold."


def test_block_attacker_script():
    """
    Verify that the block_attacker.sh script contains the correct iptables command
    to drop incoming TCP traffic from the attacker's IP (192.168.1.55).
    """
    script_path = "/home/user/block_attacker.sh"

    assert os.path.exists(script_path), f"Bash script missing: {script_path}"

    with open(script_path, 'r') as f:
        content = f.read()

    # Check for key components of the iptables command
    assert "iptables" in content, "iptables command not found in the script."
    assert "192.168.1.55" in content, "Attacker IP 192.168.1.55 not found in the script."
    assert "-p tcp" in content or "--protocol tcp" in content, "TCP protocol flag missing."
    assert "-j DROP" in content or "--jump DROP" in content, "DROP target missing."

    # Check for INPUT chain insertion/append
    assert "-A INPUT" in content or "-I INPUT" in content or "--append INPUT" in content or "--insert INPUT" in content, "INPUT chain rule missing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
