#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import secrets
import subprocess


def expected_payload(challenge):
    reversed_challenge = challenge[::-1]
    token = base64.b64encode(reversed_challenge.encode("utf-8")).decode("ascii")
    payload_str = "COMMAND:flag_captured_successfully"
    xor_key = len(challenge)
    xored_bytes = bytes([ord(c) ^ xor_key for c in payload_str])
    encoded_payload = base64.b64encode(xored_bytes).decode("ascii")
    return f"{token}.{encoded_payload}"


def test_crafter_source_exists():
    """Verify that the C++ source file exists."""
    source_file = "/home/user/crafter.cpp"
    assert os.path.exists(source_file), f"Source file missing: {source_file}"
    assert os.path.isfile(source_file), f"Path is not a file: {source_file}"


def test_crafter_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    executable = "/home/user/crafter"
    assert os.path.exists(executable), f"Executable missing: {executable}. Did you compile crafter.cpp?"
    assert os.path.isfile(executable), f"Path is not a file: {executable}"
    assert os.access(executable, os.X_OK), f"File is not executable: {executable}"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled executable is not an ELF binary: {executable}"


def test_evasion_payload_correct():
    """Verify that the evasion payload was generated correctly based on the challenge file."""
    challenge_file = "/home/user/challenge.txt"
    payload_file = "/home/user/evasion_payload.txt"

    assert os.path.exists(challenge_file), f"Challenge file missing: {challenge_file}"
    assert os.path.exists(payload_file), f"Payload file missing: {payload_file}. Did you run the executable?"

    with open(challenge_file, "r") as f:
        challenge = f.read().replace('\n', '')

    reversed_challenge = challenge[::-1]
    expected_token = base64.b64encode(reversed_challenge.encode('utf-8')).decode('utf-8')

    payload_str = "COMMAND:flag_captured_successfully"
    xor_key = len(challenge)
    xored_bytes = bytes([ord(c) ^ xor_key for c in payload_str])
    expected_encoded_payload = base64.b64encode(xored_bytes).decode('utf-8')

    expected_final_content = f"{expected_token}.{expected_encoded_payload}"

    with open(payload_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_final_content, (
        f"The evasion payload is incorrect.\n"
        f"Expected: {expected_final_content}\n"
        f"Got:      {actual_content}"
    )


def test_source_and_submitted_executable_generate_dynamic_payloads():
    source_file = "/home/user/crafter.cpp"
    submitted_executable = "/home/user/crafter"
    challenge_file = "/home/user/challenge.txt"
    payload_file = "/home/user/evasion_payload.txt"
    rebuilt_executable = f"/tmp/crafter_from_source_{secrets.token_hex(8)}"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", source_file, "-o", rebuilt_executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "crafter.cpp did not compile successfully:\n" + compile_result.stderr
    )
    assert os.path.isfile(rebuilt_executable) and os.access(rebuilt_executable, os.X_OK)

    with open(challenge_file, "rb") as f:
        original_challenge = f.read()
    with open(payload_file, "rb") as f:
        original_payload = f.read()

    nonce = secrets.token_urlsafe(18).replace("-", "A").replace("_", "B")
    challenges = [
        "X" + nonce[:7],
        "dynamic-" + nonce[:15],
        "LONG_CHALLENGE_" + nonce + "_37",
    ]

    try:
        for executable in (submitted_executable, rebuilt_executable):
            for challenge in challenges:
                with open(challenge_file, "w", encoding="ascii") as f:
                    f.write(challenge)
                if os.path.lexists(payload_file):
                    os.remove(payload_file)

                result = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                assert result.returncode == 0, (
                    f"{executable} failed for a runtime challenge with exit code "
                    f"{result.returncode}. stderr: {result.stderr.decode(errors='replace')}"
                )
                assert os.path.isfile(payload_file), (
                    f"{executable} did not create {payload_file} when executed"
                )
                with open(challenge_file, "r", encoding="ascii") as f:
                    assert f.read() == challenge, f"{executable} modified the challenge file"
                with open(payload_file, "r", encoding="ascii") as f:
                    actual = f.read().strip()
                assert actual == expected_payload(challenge), (
                    f"{executable} did not dynamically generate the correct payload "
                    f"for a verifier-supplied challenge"
                )
    finally:
        with open(challenge_file, "wb") as f:
            f.write(original_challenge)
        with open(payload_file, "wb") as f:
            f.write(original_payload)
        if os.path.exists(rebuilt_executable):
            os.remove(rebuilt_executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
