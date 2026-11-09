#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import secrets
import subprocess
import pytest

EXPECTED_REDACTED_CONTENT = (
    "[2023-10-01T12:00:00Z] GET /login?redirect=http://evil.com&password=[REDACTED]&token=[REDACTED] HTTP/1.1\n"
    "[2023-10-01T12:05:00Z] GET /login?redirect=/home&password=[REDACTED]&token=[REDACTED] HTTP/1.1\n"
    "[2023-10-01T12:10:00Z] GET /login?token=[REDACTED]&password=[REDACTED]&redirect=/dashboard HTTP/1.1\n"
)

def test_redacted_hash():
    hash_file = "/home/user/archive/redacted_hash.txt"
    assert os.path.isfile(hash_file), f"Hash file {hash_file} does not exist."

    with open(hash_file, "r") as f:
        content = f.read().strip()

    expected_hash = hashlib.sha256(EXPECTED_REDACTED_CONTENT.encode('utf-8')).hexdigest()

    # sha256sum output is typically "<hash>  <filename>"
    assert content.startswith(expected_hash), f"The hash in {hash_file} does not match the expected SHA-256 of the redacted log."

def test_encryption_verification():
    enc_file = "/home/user/archive/access_redacted.log.enc"
    key_file = "/home/user/keys/backup.key"

    assert os.path.isfile(enc_file), f"Encrypted file {enc_file} does not exist."
    assert os.path.isfile(key_file), f"Key file {key_file} is missing."

    # Decrypt using openssl
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-pass", f"file:{key_file}",
        "-in", enc_file
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        decrypted_content = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decrypt {enc_file}. OpenSSL error: {e.stderr}")

    assert decrypted_content == EXPECTED_REDACTED_CONTENT, "Decrypted content does not match the expected redacted log."

def test_plaintext_deletion():
    plaintext_file = "/home/user/app/logs/access_redacted.log"
    assert not os.path.exists(plaintext_file), f"Plaintext redacted log {plaintext_file} was not deleted."

def test_credential_rotation():
    config_file = "/home/user/app/config.env"
    assert os.path.isfile(config_file), f"Config file {config_file} does not exist."

    with open(config_file, "r") as f:
        lines = f.read().splitlines()

    new_password = "SuperSecurePwd2024!"
    expected_hash = hashlib.sha256(new_password.encode('utf-8')).hexdigest()

    expected_lines = [
        "DB_HOST=localhost",
        "DB_USER=admin",
        f"DB_PASSWORD={expected_hash}",
        "DB_PORT=5432"
    ]

    assert lines == expected_lines, f"The contents of {config_file} are incorrect. Check if the password was hashed properly and other lines remained unchanged."

def test_z_incident_response_script_executes_and_performs_work():
    script = "/home/user/incident_response.sh"
    assert os.path.lexists(script), f"Required script {script} does not exist."

    script_stat = os.lstat(script)
    assert stat.S_ISREG(script_stat.st_mode), f"{script} is not a regular file."
    assert script_stat.st_mode & 0o111, f"{script} is not executable."

    with open(script, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, \
        f"{script} is not an executable Bash script."

    password1 = secrets.token_hex(12)
    password2 = secrets.token_hex(13)
    token1 = secrets.token_hex(14)
    token2 = secrets.token_hex(15)
    old_db_password = secrets.token_hex(16)
    backup_key = secrets.token_hex(32)

    source_content = (
        f"[2031-04-05T01:02:03Z] GET /login?password={password1}&next=/account&token={token1} HTTP/1.1\n"
        f"[2031-04-05T01:03:04Z] GET /oauth?token={token2}&password={password2} HTTP/1.1\n"
    )
    expected_redacted = (
        "[2031-04-05T01:02:03Z] GET /login?password=[REDACTED]&next=/account&token=[REDACTED] HTTP/1.1\n"
        "[2031-04-05T01:03:04Z] GET /oauth?token=[REDACTED]&password=[REDACTED] HTTP/1.1\n"
    )
    config_content = (
        "DB_HOST=db.internal\n"
        "DB_USER=incident_test\n"
        f"DB_PASSWORD={old_db_password}\n"
        "DB_PORT=6543\n"
    )

    os.makedirs("/home/user/app/logs", exist_ok=True)
    os.makedirs("/home/user/app", exist_ok=True)
    os.makedirs("/home/user/archive", exist_ok=True)
    os.makedirs("/home/user/keys", exist_ok=True)

    with open("/home/user/app/logs/access.log", "w") as f:
        f.write(source_content)
    with open("/home/user/app/config.env", "w") as f:
        f.write(config_content)
    with open("/home/user/keys/backup.key", "w") as f:
        f.write(backup_key + "\n")

    for path in (
        "/home/user/app/logs/access_redacted.log",
        "/home/user/archive/redacted_hash.txt",
        "/home/user/archive/access_redacted.log.enc",
    ):
        if os.path.lexists(path):
            os.remove(path)

    try:
        result = subprocess.run(
            [script],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        pytest.fail(f"Failed to execute {script}: {e}")

    assert result.returncode == 0, (
        f"{script} exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )

    plaintext_file = "/home/user/app/logs/access_redacted.log"
    hash_file = "/home/user/archive/redacted_hash.txt"
    enc_file = "/home/user/archive/access_redacted.log.enc"

    assert not os.path.exists(plaintext_file), f"{script} did not delete the plaintext redacted log."
    assert os.path.isfile(hash_file), f"{script} did not create {hash_file}."
    assert os.path.isfile(enc_file), f"{script} did not create {enc_file}."

    expected_hash = hashlib.sha256(expected_redacted.encode("utf-8")).hexdigest()
    with open(hash_file, "r") as f:
        hash_output = f.read()
    assert hash_output == f"{expected_hash}  {plaintext_file}\n", \
        "The script did not save the standard sha256sum output for the generated redacted log."

    decrypt = subprocess.run(
        [
            "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
            "-pass", "file:/home/user/keys/backup.key",
            "-in", enc_file,
        ],
        capture_output=True,
        check=False,
    )
    assert decrypt.returncode == 0, f"The script's encrypted output could not be decrypted: {decrypt.stderr!r}"
    assert decrypt.stdout == expected_redacted.encode("utf-8"), \
        "Executing the script did not redact the supplied password and token values correctly."

    expected_password_hash = hashlib.sha256(b"SuperSecurePwd2024!").hexdigest()
    with open("/home/user/app/config.env", "r") as f:
        resulting_config = f.read().splitlines()
    assert resulting_config == [
        "DB_HOST=db.internal",
        "DB_USER=incident_test",
        f"DB_PASSWORD={expected_password_hash}",
        "DB_PORT=6543",
    ], "Executing the script did not correctly rotate the database password while preserving the config."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
