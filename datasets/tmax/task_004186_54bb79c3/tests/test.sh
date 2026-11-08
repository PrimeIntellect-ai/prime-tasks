#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import hashlib
import base64
import secrets
import subprocess
import tempfile

VAULT_PATH = '/home/user/vault.txt'
SOURCE_PATH = '/home/user/auth_service.cpp'
BINARY_PATH = '/home/user/auth_service_secure'
LOG_PATH = '/home/user/secure_hash.log'


def test_vault_permissions():
    assert os.path.exists(VAULT_PATH), f"Vault file {VAULT_PATH} does not exist."
    st = os.stat(VAULT_PATH)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Permissions of {VAULT_PATH} must be 0400, but found {oct(permissions)}."


def test_binary_exists_and_executable():
    assert os.path.exists(BINARY_PATH), f"Compiled binary {BINARY_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not a compiled executable."


def test_secure_hash_log():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist. Did you run the compiled binary?"

    with open(VAULT_PATH, 'r') as f:
        password_with_newline = f.read()

    password = password_with_newline.rstrip('\n')
    digest = hashlib.sha256(password.encode('utf-8')).digest()
    expected_b64 = base64.b64encode(digest).decode('utf-8')

    with open(LOG_PATH, 'r') as f:
        log_content = f.read().strip()

    assert log_content == expected_b64, f"Content of {LOG_PATH} is incorrect. Expected '{expected_b64}', got '{log_content}'."


def run_and_check(executable, vault_contents, args=()):
    with open(VAULT_PATH, 'wb') as f:
        f.write(vault_contents)
    os.chmod(VAULT_PATH, 0o400)

    try:
        os.unlink(LOG_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(LOG_PATH), f"{executable} did not create {LOG_PATH}."

    password = vault_contents.rstrip(b'\n')
    expected = base64.b64encode(hashlib.sha256(password).digest())
    with open(LOG_PATH, 'rb') as f:
        actual = f.read()
    assert actual == expected, (
        f"{executable} did not hash the vault contents correctly or wrote extra data. "
        f"Expected {expected!r}, got {actual!r}."
    )


def test_source_and_executable_use_vault():
    assert os.path.exists(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."

    with open(VAULT_PATH, 'rb') as f:
        original_vault = f.read()
    original_mode = stat.S_IMODE(os.stat(VAULT_PATH).st_mode)
    log_existed = os.path.exists(LOG_PATH)
    original_log = None
    if log_existed:
        with open(LOG_PATH, 'rb') as f:
            original_log = f.read()

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            rebuilt = os.path.join(tmpdir, 'auth_service_from_source')
            compile_result = subprocess.run(
                ['g++', '-std=c++17', SOURCE_PATH, '-o', rebuilt, '-lcrypto'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert compile_result.returncode == 0, (
                f"Updated source did not compile: "
                f"{compile_result.stderr.decode(errors='replace')}"
            )

            executables = (BINARY_PATH, rebuilt)
            for executable in executables:
                secret1 = ('vault-' + secrets.token_hex(24)).encode() + b'\n'
                run_and_check(executable, secret1)

                secret2 = ('second-' + secrets.token_urlsafe(28)).encode() + b'\n\n'
                run_and_check(executable, secret2, args=('command-line-decoy',))
    finally:
        with open(VAULT_PATH, 'wb') as f:
            f.write(original_vault)
        os.chmod(VAULT_PATH, original_mode)
        if log_existed:
            with open(LOG_PATH, 'wb') as f:
                f.write(original_log)
        else:
            try:
                os.unlink(LOG_PATH)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
