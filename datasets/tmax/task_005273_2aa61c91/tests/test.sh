#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import string
import binascii

SSH_DIR = "/home/user/.ssh"
AUTH_KEYS_FILE = "/home/user/.ssh/authorized_keys"
AGENT_DECODER = "/home/user/decoder.py"

LEGITIMATE_KEYS = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC1 legit@server1",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3 legit@server2",
]


def test_ssh_permissions():
    """Verify that SSH directory and authorized_keys have secure permissions."""
    assert os.path.isdir(SSH_DIR), f"SSH directory missing at {SSH_DIR}"
    assert os.path.isfile(AUTH_KEYS_FILE), f"authorized_keys missing at {AUTH_KEYS_FILE}"

    dir_mode = stat.S_IMODE(os.stat(SSH_DIR).st_mode)
    file_mode = stat.S_IMODE(os.stat(AUTH_KEYS_FILE).st_mode)

    assert dir_mode == 0o700, f"Expected {SSH_DIR} permissions to be 700, got {oct(dir_mode)}"
    assert file_mode in (0o600, 0o644), f"Expected {AUTH_KEYS_FILE} permissions to be 600 or 644, got {oct(file_mode)}"


def test_backdoor_removed():
    """Verify that the backdoor key is removed and both legitimate keys remain unchanged."""
    with open(AUTH_KEYS_FILE, "r") as f:
        lines = f.readlines()

    for line in lines:
        assert "hacker@c2-server" not in line, "Backdoor key 'hacker@c2-server' was not removed from authorized_keys"

    valid_keys = [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]
    assert len(valid_keys) > 0, "All keys were removed from authorized_keys, expected legitimate keys to remain"

    for legitimate_key in LEGITIMATE_KEYS:
        assert legitimate_key in valid_keys, f"Legitimate key was removed or altered: {legitimate_key}"


def test_decoder_exists():
    """Verify that the agent created the decoder script."""
    assert os.path.isfile(AGENT_DECODER), f"Agent decoder script missing at {AGENT_DECODER}"


def generate_fuzz_input(length):
    """Generate a random hex string representing ASCII text XORed with 170."""
    ascii_chars = string.ascii_letters + string.digits + string.punctuation + " "
    plain_text = "".join(random.choice(ascii_chars) for _ in range(length))
    obfuscated_bytes = bytes(ord(c) ^ 170 for c in plain_text)
    return binascii.hexlify(obfuscated_bytes).decode("utf-8")


def expected_output(hex_input):
    raw_bytes = binascii.unhexlify(hex_input)
    decoded = bytes(b ^ 170 for b in raw_bytes)
    return decoded.decode("utf-8", errors="replace")


def test_decoder_fuzz_equivalence():
    """Fuzz the agent's decoder against independently derived expected output."""
    random.seed(42)
    num_iterations = 100

    for i in range(num_iterations):
        byte_length = random.randint(5, 100)
        hex_input = generate_fuzz_input(byte_length)
        oracle_output = expected_output(hex_input)

        agent_proc = subprocess.run(
            ["python3", AGENT_DECODER, hex_input],
            capture_output=True,
            text=True
        )
        agent_output = agent_proc.stdout

        assert agent_proc.returncode == 0, f"Agent decoder failed with return code {agent_proc.returncode} on input {hex_input}\nStderr: {agent_proc.stderr}"
        assert agent_output == oracle_output, f"Mismatch on input {hex_input}.\nExpected: {repr(oracle_output)}\nGot (Agent): {repr(agent_output)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
