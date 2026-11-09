#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_attacker_ip_extracted():
    ip_file = "/home/user/attacker_ip.txt"
    assert os.path.isfile(ip_file), f"The file {ip_file} is missing. Did you save the attacker's IP?"

    with open(ip_file, "r") as f:
        content = f.read()

    extracted_ip = content.strip()
    assert extracted_ip == "192.168.14.88", f"The attacker IP in {ip_file} is incorrect. Found: '{extracted_ip}'"

def test_flag_extracted():
    flag_file = "/home/user/flag.txt"
    assert os.path.isfile(flag_file), f"The file {flag_file} is missing. Did you save the extracted flag?"

    with open(flag_file, "r") as f:
        content = f.read()

    extracted_flag = content.strip()
    assert extracted_flag == "FLAG{b4sh_x0r_m4st3r}", f"The flag in {flag_file} is incorrect. Found: '{extracted_flag}'"

def test_no_extra_content():
    ip_file = "/home/user/attacker_ip.txt"
    flag_file = "/home/user/flag.txt"

    if os.path.isfile(ip_file):
        with open(ip_file, "r") as f:
            content = f.read()
            # Ensure no extra spaces or newlines other than a possible single trailing newline
            assert content in ["192.168.14.88", "192.168.14.88\n"], "The attacker_ip.txt file contains extra spaces or newlines."

    if os.path.isfile(flag_file):
        with open(flag_file, "r") as f:
            content = f.read()
            assert content in ["FLAG{b4sh_x0r_m4st3r}", "FLAG{b4sh_x0r_m4st3r}\n"], "The flag.txt file contains extra spaces or newlines."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
