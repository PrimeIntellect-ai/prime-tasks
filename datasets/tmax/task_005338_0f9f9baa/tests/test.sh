#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import contextlib
import os
import re
import secrets
import shutil
import subprocess

TARGET = "/home/user/managed_authorized_keys"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


@contextlib.contextmanager
def isolated_target():
    backup = TARGET + ".verifier-backup-" + secrets.token_hex(12)
    had_target = os.path.lexists(TARGET)
    if had_target:
        os.rename(TARGET, backup)
    try:
        yield
    finally:
        if os.path.lexists(TARGET):
            remove_path(TARGET)
        if had_target and os.path.lexists(backup):
            os.rename(backup, TARGET)


def run_program(executable, args):
    return subprocess.run(
        [executable] + args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )


def verify_key_manager_behavior(executable):
    nonce = secrets.token_hex(12)
    marker = "/tmp/key_manager_injection_" + nonce
    payload = "ssh-ed25519 AAAA" + nonce + " verifier'; touch " + marker + "; echo 'tail"
    initial = b"existing-key\n"

    if os.path.lexists(marker):
        remove_path(marker)

    try:
        with isolated_target():
            with open(TARGET, "wb") as output:
                output.write(initial)

            result = run_program(executable, [payload])
            assert result.returncode == 0, (
                f"{executable} returned {result.returncode} while appending a valid key; "
                f"stderr={result.stderr!r}"
            )

            with open(TARGET, "rb") as output:
                actual = output.read()
            expected = initial + payload.encode("ascii") + b"\n"
            assert actual == expected, (
                "key_manager did not append the argument exactly as one literal key line"
            )
            assert not os.path.exists(marker), (
                "Shell metacharacters in the key were executed instead of being written literally"
            )

            unchanged = actual
            no_argument = run_program(executable, [])
            assert no_argument.returncode == 1, "key_manager must return 1 when no key is provided"
            extra_argument = run_program(executable, [payload, "unexpected-extra-argument"])
            assert extra_argument.returncode == 1, "key_manager must return 1 for an invalid argument count"
            with open(TARGET, "rb") as output:
                assert output.read() == unchanged, "Invalid invocations must not modify authorized_keys"

        with isolated_target():
            os.mkdir(TARGET)
            failed_open = run_program(executable, [payload])
            assert failed_open.returncode == 1, (
                "key_manager must return 1 when the target cannot be opened as a file"
            )
            assert os.path.isdir(TARGET), "key_manager unexpectedly replaced the failed-open target"
    finally:
        if os.path.lexists(marker):
            remove_path(marker)


def test_decrypted_token():
    path = "/home/user/decrypted_token.txt"
    assert os.path.exists(path), f"File not found: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_token = "AUTH_TOKEN_9a8b7c6d5e4f3g2h1"
    assert content == expected_token, f"Decrypted token is incorrect. Expected '{expected_token}', got '{content}'"


def test_key_manager_c_fixed():
    path = "/home/user/key_manager.c"
    assert os.path.exists(path), f"File not found: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "system" not in content, "The vulnerable 'system' function call is still present in key_manager.c"
    assert "fopen" in content, "The secure 'fopen' function is missing in key_manager.c"
    assert "fprintf" in content or "fputs" in content, "A secure file writing function (like fprintf or fputs) is missing in key_manager.c"
    assert "/home/user/managed_authorized_keys" in content, "The target file path '/home/user/managed_authorized_keys' is missing in key_manager.c"


def test_key_manager_executable():
    path = "/home/user/key_manager"
    assert os.path.exists(path), f"Executable not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

    with open(path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File is not a valid ELF executable: {path}"


def test_key_manager_source_and_binary_behavior():
    source = "/home/user/key_manager.c"
    rebuilt = "/tmp/key_manager_rebuilt_" + secrets.token_hex(12)
    try:
        compilation = subprocess.run(
            ["gcc", "-std=c11", source, "-o", rebuilt],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compilation.returncode == 0, (
            f"Submitted key_manager.c does not compile; stderr={compilation.stderr!r}"
        )
        verify_key_manager_behavior(rebuilt)
        verify_key_manager_behavior("/home/user/key_manager")
    finally:
        if os.path.lexists(rebuilt):
            remove_path(rebuilt)


def test_sshd_config_hardened():
    path = "/home/user/sshd_config"
    assert os.path.exists(path), f"File not found: {path}"

    with open(path, "r") as f:
        lines = f.readlines()

    permit_root_login_no = False
    password_auth_no = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        # Check PermitRootLogin
        if re.match(r"^PermitRootLogin\s+yes\b", line, re.IGNORECASE):
            assert False, "Found uncommented 'PermitRootLogin yes' in sshd_config"
        if re.match(r"^PermitRootLogin\s+no\b", line, re.IGNORECASE):
            permit_root_login_no = True

        # Check PasswordAuthentication
        if re.match(r"^PasswordAuthentication\s+yes\b", line, re.IGNORECASE):
            assert False, "Found uncommented 'PasswordAuthentication yes' in sshd_config"
        if re.match(r"^PasswordAuthentication\s+no\b", line, re.IGNORECASE):
            password_auth_no = True

    assert permit_root_login_no, "'PermitRootLogin no' is missing or commented out in sshd_config"
    assert password_auth_no, "'PasswordAuthentication no' is missing or commented out in sshd_config"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
