#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

LOG_PATH = "/home/user/access.log"
INCIDENT_CIPHERTEXT = "7a6e6f7364687e78697e7f640202"
KNOWN_PREFIX = b"AUTH_"


def incident_from_log():
    with open(LOG_PATH, "r") as f:
        matching = [line.strip() for line in f if "evil.com" in line]
    assert len(matching) == 1, "access.log should contain exactly one evil.com incident."

    match = re.match(r"^(\S+).*?[?&]token=([0-9a-fA-F]+)", matching[0])
    assert match, "Could not extract the attacker IP and token from access.log."
    return match.group(1), match.group(2).lower()


def recovered_key():
    ciphertext = bytes.fromhex(INCIDENT_CIPHERTEXT)
    candidates = {ciphertext[i] ^ KNOWN_PREFIX[i] for i in range(len(KNOWN_PREFIX))}
    assert len(candidates) == 1, "The known plaintext prefix does not yield one XOR key."
    return candidates.pop()


def decrypt(ciphertext_hex):
    key = recovered_key()
    return bytes(value ^ key for value in bytes.fromhex(ciphertext_hex))


def test_block_rules_sh():
    script_path = "/home/user/block_rules.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} does not have execution permissions."

    with open(script_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith("#")]
    assert len(lines) == 1, f"{script_path} should contain exactly one iptables command."
    assert lines[0] == "iptables -A INPUT -s 198.51.100.42 -j DROP", f"{script_path} contains incorrect iptables command."

    attacker_ip, stolen_ciphertext = incident_from_log()
    assert stolen_ciphertext == INCIDENT_CIPHERTEXT, "The incident ciphertext in access.log is unexpected."
    assert lines[0] == f"iptables -A INPUT -s {attacker_ip} -j DROP"


def test_audit_token_txt():
    token_path = "/home/user/audit_token.txt"
    assert os.path.isfile(token_path), f"{token_path} does not exist."

    with open(token_path, "r") as f:
        content = f.read().strip()

    assert content == "AUTH_SECRET_99", f"{token_path} does not contain the correct decrypted token."

    _, stolen_ciphertext = incident_from_log()
    expected = decrypt(stolen_ciphertext).decode("ascii")
    assert content == expected, f"{token_path} does not contain the decrypted token from access.log."


def test_decrypt_sh():
    script_path = "/home/user/decrypt.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    try:
        result = subprocess.run(
            ["bash", script_path, "7a6e6f7364687e78697e7f640202"],
            capture_output=True,
            text=True,
            timeout=5
        )
        assert "AUTH_SECRET_99" in result.stdout.strip(), f"{script_path} did not output the correct plaintext for the given ciphertext."
    except Exception as e:
        assert False, f"Failed to execute {script_path}: {e}"


def test_decrypt_sh_uses_argument_and_xor_key():
    script_path = "/home/user/decrypt.sh"
    key = recovered_key()

    # Unpredictable ciphertexts prevent a fixed-output or fixed-subset implementation
    # from passing while still exercising valid AUTH_-prefixed tokens.
    for _ in range(8):
        plaintext = ("AUTH_" + secrets.token_hex(secrets.randbelow(24) + 4)).encode("ascii")
        ciphertext = bytes(value ^ key for value in plaintext).hex()
        result = subprocess.run(
            ["bash", script_path, ciphertext],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5
        )
        assert result.returncode == 0, (
            f"{script_path} failed for a valid ciphertext: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert result.stdout.rstrip(b"\r\n") == plaintext, (
            f"{script_path} did not XOR-decrypt its ciphertext argument correctly."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
