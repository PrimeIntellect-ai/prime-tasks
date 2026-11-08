#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import ctypes
import subprocess
import hashlib
import secrets
import string
import tempfile
import pytest


def test_ssh_authorized_keys_cleaned():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"File not found: {auth_keys_path}"

    with open(auth_keys_path, "r") as f:
        content = f.read()

    assert "evil@hacker.com" not in content, "The attacker's SSH key (evil@hacker.com) was not removed."
    assert "good@user.com" in content, "A legitimate SSH key (good@user.com) was incorrectly removed."
    assert "admin@company.com" in content, "A legitimate SSH key (admin@company.com) was incorrectly removed."


def test_admin_token_forged():
    token_path = "/home/user/admin_token.txt"
    assert os.path.isfile(token_path), f"File not found: {token_path}"

    # Compute the expected token using glibc's rand()
    try:
        libc = ctypes.CDLL("libc.so.6")
    except OSError:
        pytest.fail("Could not load libc.so.6 to verify the token.")

    libc.srand(1700000000)
    secret = libc.rand()
    xor_byte = secret % 256

    expected_token = "".join(f"{ord(c) ^ xor_byte:02x}" for c in "admin")

    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token == expected_token, f"The forged token in {token_path} is incorrect."


def test_auth_daemon_fixed():
    binary_path = "/home/user/auth_daemon_fixed"
    source_path = "/home/user/auth_daemon.cpp"

    assert os.path.isfile(binary_path), f"Compiled binary not found: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"File is not executable: {binary_path}"

    # Ensure the submitted executable is a compiled ELF binary, not a script.
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The compiled deliverable is not an ELF binary: {binary_path}"

    # Preserve the original source assertions.
    with open(source_path, "r") as f:
        source_code = f.read()

    assert "SHA256" in source_code or "EVP_sha256" in source_code, "The fixed source code does not appear to use SHA256."
    assert "SecureSecretKey" in source_code, "The fixed source code does not contain the required salt/key 'SecureSecretKey'."

    # Preserve the original executable behavior check.
    try:
        result = subprocess.run([binary_path], capture_output=True, text=True, timeout=2)
        output = result.stdout.strip()
    except Exception as e:
        pytest.fail(f"Failed to execute {binary_path}: {e}")

    expected_guest_hash = hashlib.sha256(b"guestSecureSecretKey").hexdigest()
    expected_admin_hash = hashlib.sha256(b"adminSecureSecretKey").hexdigest()

    assert output in (expected_guest_hash, expected_admin_hash), (
        f"The binary output '{output}' does not match the expected SHA-256 hash for 'guest' or 'admin' concatenated with 'SecureSecretKey'."
    )

    # Compile the submitted generate_token implementation into a verifier-owned
    # driver so it can be exercised on unpredictable usernames and timestamps.
    with tempfile.TemporaryDirectory(prefix="auth_verify_") as td:
        obj_path = os.path.join(td, "auth_daemon.o")
        driver_path = os.path.join(td, "driver.cpp")
        helper_path = os.path.join(td, "token_driver")

        compile_obj = subprocess.run(
            ["g++", "-std=c++17", "-Dmain=auth_daemon_original_main", "-c", source_path, "-o", obj_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_obj.returncode == 0, (
            "The submitted auth_daemon.cpp could not be compiled:\n"
            + compile_obj.stdout + compile_obj.stderr
        )

        with open(driver_path, "w") as f:
            f.write(r'''#include <iostream>
#include <string>
#include <stdexcept>

std::string generate_token(const std::string& username, int timestamp);

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    try {
        std::cout << generate_token(argv[1], std::stoi(argv[2])) << std::endl;
    } catch (...) {
        return 3;
    }
    return 0;
}
''')

        link_driver = subprocess.run(
            ["g++", "-std=c++17", driver_path, obj_path, "-lcrypto", "-o", helper_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert link_driver.returncode == 0, (
            "Could not link a driver against the submitted generate_token function:\n"
            + link_driver.stdout + link_driver.stderr
        )

        alphabet = string.ascii_letters + string.digits
        cases = []
        for _ in range(6):
            username = "u_" + "".join(secrets.choice(alphabet) for _ in range(12 + secrets.randbelow(12)))
            timestamp = secrets.randbelow(2_000_000_000)
            cases.append((username, timestamp))

        # Also verify that timestamp no longer affects a token.
        repeated_user = "repeat_" + "".join(secrets.choice(alphabet) for _ in range(18))
        cases.extend([(repeated_user, 1), (repeated_user, 1999999999)])

        for username, timestamp in cases:
            run = subprocess.run(
                [helper_path, username, str(timestamp)],
                capture_output=True,
                text=True,
                timeout=2,
            )
            assert run.returncode == 0, (
                f"generate_token failed for a verifier-selected input: {run.stderr}"
            )
            actual = run.stdout.strip()
            expected = hashlib.sha256((username + "SecureSecretKey").encode()).hexdigest()
            assert actual == expected, (
                "generate_token did not return the required lowercase SHA-256 hash "
                "for a verifier-selected username."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
