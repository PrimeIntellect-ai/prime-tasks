#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import stat
import subprocess
import pytest

BASE_DIR = "/home/user/web_incident"
ATTACKER_IP_FILE = os.path.join(BASE_DIR, "attacker_ip.txt")
CWE_FILE = os.path.join(BASE_DIR, "cwe.txt")
SERVER_SH = os.path.join(BASE_DIR, "server.sh")
SERVER_KEY = os.path.join(BASE_DIR, "certs/server.key")

def test_attacker_ip_identified():
    assert os.path.isfile(ATTACKER_IP_FILE), f"The file {ATTACKER_IP_FILE} does not exist."
    with open(ATTACKER_IP_FILE, "r") as f:
        content = f.read().strip()
    assert content == "172.16.0.45", f"Incorrect attacker IP identified. Found: '{content}'"

def test_cwe_identified():
    assert os.path.isfile(CWE_FILE), f"The file {CWE_FILE} does not exist."
    with open(CWE_FILE, "r") as f:
        content = f.read().strip().upper()
    assert content in ["CWE-78", "CWE-77"], f"Incorrect CWE identified. Expected CWE-78 (or CWE-77), found: '{content}'"

def test_server_sh_remediated():
    assert os.path.isfile(SERVER_SH), f"The file {SERVER_SH} does not exist."

    # Check that eval is removed
    with open(SERVER_SH, "r") as f:
        content = f.read()
    assert "eval" not in content, f"The script {SERVER_SH} still contains the insecure 'eval' command."

    # Preserve the original fixed execution check.
    test_input = "test; ls"
    try:
        result = subprocess.run(
            [SERVER_SH, test_input],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
        expected_output = f"Welcome {test_input}"
        assert output == expected_output, f"The script did not safely output the argument. Expected '{expected_output}', got '{output}'"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {SERVER_SH} failed with error: {e.stderr}")
    except PermissionError:
        pytest.fail(f"The script {SERVER_SH} is no longer executable.")

def test_server_sh_handles_unpredictable_arguments_safely():
    nonce = secrets.token_hex(16)
    canary = f"/tmp/server_sh_injection_{nonce}"
    test_inputs = [
        f"user-{nonce}",
        f"first {nonce} last",
        f"  padded-{nonce}  ",
        f"line1-{nonce}\nline2-{nonce}",
        f"x-{nonce}; touch {canary}",
        f"$(touch {canary})-{nonce}",
        f"`touch {canary}`-{nonce}",
        f"{nonce} * ? [abc] $HOME \"quoted\" 'single' \\ & |",
        "",
    ]

    if os.path.exists(canary):
        os.unlink(canary)

    for test_input in test_inputs:
        try:
            result = subprocess.run(
                [SERVER_SH, test_input],
                cwd=BASE_DIR,
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Execution of {SERVER_SH} failed for a generated argument: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Execution of {SERVER_SH} timed out for a generated argument.")
        except PermissionError:
            pytest.fail(f"The script {SERVER_SH} is no longer executable.")

        expected_output = f"Welcome {test_input}\n"
        assert result.stdout == expected_output, (
            "The script did not preserve the argument exactly and safely. "
            f"Expected {expected_output!r}, got {result.stdout!r}"
        )
        assert not os.path.exists(canary), "The supplied argument was executed as shell code."

def test_server_key_permissions_secured():
    assert os.path.isfile(SERVER_KEY), f"The file {SERVER_KEY} does not exist."

    st = os.stat(SERVER_KEY)
    perms = oct(st.st_mode)[-3:]
    assert perms == "600", f"The permissions for {SERVER_KEY} are not correctly secured. Expected 600, got {perms}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
