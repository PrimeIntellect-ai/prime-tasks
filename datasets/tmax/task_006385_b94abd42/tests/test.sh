#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid
import pytest

INCIDENT_DIR = "/home/user/incident_response"


def redact_expected(content):
    content = re.sub(r"password=[A-Za-z0-9]+", "password=REDACTED", content)
    content = re.sub(r"Bearer [A-Za-z0-9._-]+", "Bearer REDACTED", content)
    return content


def test_phase1_log_redaction():
    source_log_path = os.path.join(INCIDENT_DIR, "access.log")
    script_path = os.path.join(INCIDENT_DIR, "redact.sh")
    redacted_log_path = os.path.join(INCIDENT_DIR, "access_redacted.log")

    assert os.path.isfile(script_path), f"Redaction script not found at {script_path}"
    assert os.path.isfile(redacted_log_path), f"Redacted log file not found at {redacted_log_path}"

    with open(source_log_path, "r") as f:
        source_content = f.read()
    with open(redacted_log_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "Secret123Password" not in content, "The original password was not redacted from the log."
    assert "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" not in content, "The original Bearer token was not redacted from the log."
    assert "password=REDACTED" in content, "The string 'password=REDACTED' was not found in the redacted log."
    assert "Bearer REDACTED" in content, "The string 'Bearer REDACTED' was not found in the redacted log."

    # The complete log must be preserved, with only the specified substitutions.
    assert content == redact_expected(source_content), "access_redacted.log is not a faithful redaction of access.log."

    # Exercise redact.sh on unpredictable input rather than trusting the existing output.
    marker = uuid.uuid4().hex
    password = "Pw" + uuid.uuid4().hex
    token = uuid.uuid4().hex + "." + uuid.uuid4().hex + "-_"
    challenge = (
        f"{marker} ordinary text must remain unchanged\n"
        f"request?password={password}&next=/home\n"
        f"Authorization: Bearer {token}\n"
        f"multiple password={password} and Bearer {token} end\n"
    )
    expected_challenge = redact_expected(challenge)

    with open(source_log_path, "w") as f:
        f.write(challenge)
    if os.path.exists(redacted_log_path):
        os.remove(redacted_log_path)

    try:
        result = subprocess.run(
            ["bash", script_path],
            cwd=INCIDENT_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f"redact.sh failed when executed: {e}")

    if os.path.isfile(redacted_log_path):
        with open(redacted_log_path, "r") as f:
            actual_challenge = f.read()
    else:
        actual_challenge = result.stdout

    assert actual_challenge == expected_challenge, "redact.sh did not correctly redact and preserve dynamically supplied log data."


def test_phase2_config_rotation():
    original_enc_path = os.path.join(INCIDENT_DIR, "config.enc")
    updated_path = os.path.join(INCIDENT_DIR, "config_updated.txt")
    new_enc_path = os.path.join(INCIDENT_DIR, "config_new.enc")

    assert os.path.isfile(updated_path), f"Updated plaintext config not found at {updated_path}"
    assert os.path.isfile(new_enc_path), f"New encrypted config not found at {new_enc_path}"

    original_cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-pass", "pass:compromised_pass_123",
        "-in", original_enc_path,
    ]
    try:
        original_result = subprocess.run(original_cmd, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decrypt the supplied config.enc: {e.stderr.decode(errors='replace')}")

    original_content = original_result.stdout.decode("utf-8")
    matching_lines = re.findall(r"(?m)^DB_PASSWORD=.*$", original_content)
    assert len(matching_lines) == 1, "The supplied configuration did not contain exactly one DB_PASSWORD line."
    expected_content = re.sub(
        r"(?m)^DB_PASSWORD=.*$",
        "DB_PASSWORD=NewSecureDbPass2024!",
        original_content,
    )

    with open(updated_path, "r") as f:
        updated_content = f.read()
    assert updated_content == expected_content, "config_updated.txt does not preserve the full original configuration with only DB_PASSWORD rotated."

    decrypt_cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-pass", "pass:SecureRotation_456",
        "-in", new_enc_path,
    ]

    try:
        result = subprocess.run(decrypt_cmd, capture_output=True, text=True, check=True)
        decrypted_content = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decrypt {new_enc_path} with the new password. OpenSSL error: {e.stderr}")

    # Preserve the original assertions.
    assert "DB_PASSWORD=NewSecureDbPass2024!" in decrypted_content, "The new database password was not found in the decrypted configuration."
    assert "OldCompromisedDBPass!" not in decrypted_content, "The old compromised database password is still present in the configuration."

    assert decrypted_content == expected_content, "config_new.enc does not contain the complete updated configuration."


def test_phase3_ssh_hardening():
    sshd_config_path = os.path.join(INCIDENT_DIR, "sshd_config")
    assert os.path.isfile(sshd_config_path), f"sshd_config not found at {sshd_config_path}"

    with open(sshd_config_path, "r") as f:
        lines = f.readlines()

    active_lines = [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]

    assert "PermitRootLogin no" in active_lines, "Directive 'PermitRootLogin no' is not active in sshd_config."
    assert "PasswordAuthentication no" in active_lines, "Directive 'PasswordAuthentication no' is not active in sshd_config."
    assert not any(re.match(r"^PermitRootLogin\s+yes$", line) for line in active_lines), "'PermitRootLogin yes' is still active."
    assert not any(re.match(r"^PasswordAuthentication\s+yes$", line) for line in active_lines), "'PasswordAuthentication yes' is still active."


def test_phase3_ssh_key_rotation():
    key_path = os.path.join(INCIDENT_DIR, "new_keys/id_ed25519")
    assert os.path.isfile(key_path), f"New SSH private key not found at {key_path}"

    try:
        result = subprocess.run(["ssh-keygen", "-l", "-f", key_path], capture_output=True, text=True, check=True)
        output = result.stdout.upper()
        assert "ED25519" in output, f"The generated key is not an ED25519 key. ssh-keygen output: {output}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read the SSH key with ssh-keygen. It might be invalid or have incorrect permissions. Error: {e.stderr}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
