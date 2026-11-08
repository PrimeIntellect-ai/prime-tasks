#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import secrets
import pytest

def test_malicious_ip_file():
    filepath = "/home/user/malicious_ip.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_ip = "203.0.113.99"
    assert content == expected_ip, f"Content of {filepath} is incorrect. Expected '{expected_ip}', found '{content}'."

def test_malicious_domain_file():
    filepath = "/home/user/malicious_domain.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_domain = "xss.evil-hacker.local"
    assert content == expected_domain, f"Content of {filepath} is incorrect. Expected '{expected_domain}', found '{content}'."

def test_csp_header_file():
    filepath = "/home/user/csp_header.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_csp = "default-src 'none'; script-src 'self'; style-src 'self';"
    assert content == expected_csp, f"Content of {filepath} is incorrect. Expected '{expected_csp}', found '{content}'."

def test_generate_block_rule_script():
    filepath = "/home/user/generate_block_rule.sh"
    assert os.path.isfile(filepath), f"Script {filepath} does not exist."

    # Check if the file is executable
    st = os.stat(filepath)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Script {filepath} is not executable."

    # Test the script execution with the original input
    test_ip = "1.2.3.4"
    expected_output = f"deny {test_ip};"

    try:
        result = subprocess.run(
            [filepath, test_ip],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script {filepath} failed to execute properly. Error: {e.stderr}")
    except Exception as e:
        pytest.fail(f"An error occurred while running {filepath}: {str(e)}")

    assert output == expected_output, f"Script output is incorrect. Expected '{expected_output}', found '{output}'."

    # Exercise dynamically generated inputs so the script must use its argument.
    dynamic_ips = set()
    while len(dynamic_ips) < 3:
        dynamic_ips.add(".".join(str(secrets.randbelow(254) + 1) for _ in range(4)))

    for dynamic_ip in dynamic_ips:
        dynamic_expected = f"deny {dynamic_ip};"
        try:
            result = subprocess.run(
                [filepath, dynamic_ip],
                capture_output=True,
                text=True,
                check=True
            )
            dynamic_output = result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script {filepath} failed for input '{dynamic_ip}'. Error: {e.stderr}")
        except Exception as e:
            pytest.fail(f"An error occurred while running {filepath} with input '{dynamic_ip}': {str(e)}")

        assert dynamic_output == dynamic_expected, (
            f"Script output is incorrect for input '{dynamic_ip}'. "
            f"Expected '{dynamic_expected}', found '{dynamic_output}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
