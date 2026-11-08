#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import subprocess
import pytest

SCRIPT_PATH = "/home/user/generate_payload.sh"
PAYLOAD_PATH = "/home/user/final_payload.txt"
TARGET_STRING = "EXPLOIT_SANDBOX_ESCALATE_PID_1"


def compute_xor_hex(text: str, key: int) -> str:
    """Compute the expected single-byte XOR encoding for ASCII text."""
    return "".join(f"{ord(c) ^ key:02x}" for c in text)


def derive_key_from_supplied_files() -> int:
    with open("/home/user/known_commands.txt", "rb") as f:
        plaintext_lines = f.read().splitlines()
    with open("/home/user/audit.log.enc", "r", encoding="ascii") as f:
        encrypted_lines = [bytes.fromhex(line.strip()) for line in f if line.strip()]

    assert len(plaintext_lines) == len(encrypted_lines) and plaintext_lines, (
        "The supplied known-command and audit files do not contain matching records."
    )

    possible_keys = set()
    for plaintext, encrypted in zip(plaintext_lines, encrypted_lines):
        assert len(plaintext) == len(encrypted), "A supplied known plaintext/ciphertext pair has mismatched lengths."
        possible_keys.update(p ^ c for p, c in zip(plaintext, encrypted))

    assert len(possible_keys) == 1, "The supplied records do not use one consistent single-byte XOR key."
    return possible_keys.pop()


def run_generator(value: str):
    try:
        return subprocess.run(
            [SCRIPT_PATH, value],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {SCRIPT_PATH}: {e}")


def assert_generator_output(value: str, expected_hex: str):
    result = run_generator(value)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr.strip()}"
    )
    output = result.stdout.strip().lower()
    assert output == expected_hex.lower(), (
        f"Script did not produce the correct XOR hex output for input {value!r}. "
        f"Expected {expected_hex!r}, but got {output!r}."
    )


def test_generate_payload_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"The script {SCRIPT_PATH} is not executable. Please run 'chmod +x {SCRIPT_PATH}'."


def test_generate_payload_script_functionality():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot test functionality because {SCRIPT_PATH} is missing or not executable.")

    # Preserve the original fixed functionality assertion.
    test_string = "Test_String_123"
    key = 0x4B
    expected_hex = compute_xor_hex(test_string, key)
    assert_generator_output(test_string, expected_hex)


def test_generate_payload_script_on_unpredictable_inputs():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot test functionality because {SCRIPT_PATH} is missing or not executable.")

    key = derive_key_from_supplied_files()
    alphabet = string.ascii_letters + string.digits + " _-./:@+=,!?%[]{}"

    # These values are generated only after the agent has finished, preventing a
    # fixed lookup table for the one public sample from satisfying the verifier.
    cases = []
    for length in (1, 5, 17, 31, 64, 97):
        cases.append("".join(secrets.choice(alphabet) for _ in range(length)))

    for value in cases:
        assert_generator_output(value, compute_xor_hex(value, key))


def test_final_payload_file():
    assert os.path.exists(PAYLOAD_PATH), f"The final payload file {PAYLOAD_PATH} is missing."
    assert os.path.isfile(PAYLOAD_PATH), f"The path {PAYLOAD_PATH} is not a regular file."

    with open(PAYLOAD_PATH, "r") as f:
        content = f.read().strip().lower()

    # Preserve the original independently computed final-payload assertion.
    key = 0x4B
    expected_hex = compute_xor_hex(TARGET_STRING, key)
    assert content == expected_hex, (
        f"The contents of {PAYLOAD_PATH} do not match the expected encrypted payload for {TARGET_STRING!r}. "
        f"Expected {expected_hex!r}, but got {content!r}."
    )

    # Also ensure the submitted generator itself produces the saved target payload.
    derived_key = derive_key_from_supplied_files()
    assert_generator_output(TARGET_STRING, compute_xor_hex(TARGET_STRING, derived_key))
    generated = run_generator(TARGET_STRING)
    assert generated.stdout.strip().lower() == content, (
        "The saved final payload does not match the submitted generator's output for the target string."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
