#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

EXPLOIT_SOURCE = "/home/user/exploit.cpp"
EXPLOIT_BINARY = "/home/user/exploit"
TOKEN_PATH = "/home/user/forged_token.txt"
KEY_PATH = "/home/user/ssh_keys/service_ed25519.pub"
PAYLOAD = b"admin|root|NONE"


def expected_token(key):
    assert key, "Test key must not be empty"
    return bytes(p ^ key[i % len(key)] for i, p in enumerate(PAYLOAD)).hex().upper()


def run_exploit(path, key):
    with open(KEY_PATH, "wb") as f:
        f.write(key)

    result = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; "
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )

    try:
        output = result.stdout.decode("ascii")
    except UnicodeDecodeError as exc:
        raise AssertionError(f"{path} did not emit an ASCII hexadecimal token") from exc

    lines = output.splitlines()
    assert len(lines) == 1, f"{path} must emit exactly one line, got {output!r}"
    assert lines[0] == expected_token(key), (
        f"{path} produced the wrong token for the key supplied at {KEY_PATH}"
    )


def test_exploit_source_exists():
    """Verify that the student wrote the exploit source code."""
    path = EXPLOIT_SOURCE
    assert os.path.isfile(path), f"Exploit source code is missing at {path}"
    assert os.path.getsize(path) > 0, f"Exploit source code at {path} is empty"


def test_exploit_binary_exists_and_executable():
    """Verify that the exploit was compiled and is executable."""
    path = EXPLOIT_BINARY
    assert os.path.isfile(path), f"Compiled exploit binary is missing at {path}"
    assert os.access(path, os.X_OK), f"Compiled exploit binary at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled exploit at {path} is not an ELF binary"


def test_forged_token_correct():
    """Verify that the forged token matches the expected XORed and hex-encoded output."""
    token_path = TOKEN_PATH
    key_path = KEY_PATH

    assert os.path.isfile(token_path), f"Forged token file is missing at {token_path}"
    assert os.path.isfile(key_path), f"SSH public key file is missing at {key_path}"

    with open(key_path, "rb") as f:
        key = f.read()

    payload = b"admin|root|NONE"

    # Recompute the expected XORed hex string
    xored = bytes(p ^ key[i % len(key)] for i, p in enumerate(payload))
    expected_hex = xored.hex().upper()

    with open(token_path, "r") as f:
        actual_hex = f.read().strip().upper()

    assert actual_hex == expected_hex, (
        f"The forged token in {token_path} is incorrect. "
        f"Expected {expected_hex}, but got {actual_hex}."
    )


def test_submitted_source_and_binary_implement_exploit():
    """Rebuild the submitted C++ and exercise both artifacts with unpredictable keys."""
    with open(KEY_PATH, "rb") as f:
        original_key = f.read()

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "exploit-rebuilt")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", EXPLOIT_SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "The submitted exploit.cpp does not compile: "
            + compile_result.stderr.decode("utf-8", errors="replace")
        )

        # Include short keys to exercise repeating-key XOR and a longer key to
        # ensure the output is derived from the file rather than hardcoded.
        alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        keys = []
        for length in (3, 9, 37):
            random_bytes = secrets.token_bytes(length)
            keys.append(bytes(alphabet[b % len(alphabet)] for b in random_bytes))

        try:
            for executable in (EXPLOIT_BINARY, rebuilt):
                for key in keys:
                    run_exploit(executable, key)
        finally:
            with open(KEY_PATH, "wb") as f:
                f.write(original_key)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
