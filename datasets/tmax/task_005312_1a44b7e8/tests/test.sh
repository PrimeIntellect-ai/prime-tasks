#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import hashlib
import subprocess
import uuid
import pytest

UPLOAD_DIR = "/home/user/incoming_uploads"
CERTS_DIR = "/home/user/certs"
AUTH_KEYS_DIR = "/home/user/auth_keys"
TOKEN_PATH = "/home/user/auth_keys/master_token.txt"
EXPLOIT_PATH = "/home/user/incoming_uploads/exploit.job"
VULNERABLE_SCRIPT = "/home/user/cred_rotator.sh"
SECURE_SCRIPT = "/home/user/cred_rotator_secure.sh"


def read_exploit():
    assert os.path.isfile(EXPLOIT_PATH), f"Exploit job file {EXPLOIT_PATH} does not exist."
    with open(EXPLOIT_PATH, "r") as f:
        content = f.read().strip()

    assert ":" in content, "Exploit job file does not contain the required ':' separator."
    filename, encoded_data = content.split(":", 1)
    assert "../" in filename, "Exploit job file does not appear to contain a path traversal payload."

    try:
        decoded_bytes = base64.b64decode(encoded_data, validate=True)
        decoded_data = decoded_bytes.decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to decode base64 data in exploit job: {e}")

    assert "ROTATED_SECRET_999" in decoded_data, "Decoded data does not contain the expected secret."
    assert decoded_bytes == b"ROTATED_SECRET_999\n", "Exploit payload does not decode to the exact required token contents."

    resolved_target = os.path.abspath(os.path.join(CERTS_DIR, filename))
    assert resolved_target == TOKEN_PATH, (
        f"Traversal filename resolves to {resolved_target}, not {TOKEN_PATH}."
    )
    return filename, encoded_data


def test_exploit_job_exists_and_format():
    read_exploit()


def test_exploit_actually_rotates_token_when_vulnerable_script_runs():
    read_exploit()
    assert os.path.isfile(VULNERABLE_SCRIPT), f"Vulnerable script {VULNERABLE_SCRIPT} does not exist."

    # Isolate the submitted exploit so unrelated jobs cannot perform the rotation.
    for name in os.listdir(UPLOAD_DIR):
        path = os.path.join(UPLOAD_DIR, name)
        if name.endswith(".job") and path != EXPLOIT_PATH:
            os.remove(path)

    # Undo any directly-written answer, then require execution of the vulnerable
    # rotator with exploit.job to produce the requested token.
    with open(TOKEN_PATH, "wb") as f:
        f.write(b"OLD_SECRET_123\n")

    result = subprocess.run([VULNERABLE_SCRIPT], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Vulnerable script execution failed: {result.stderr}"

    with open(TOKEN_PATH, "rb") as f:
        content = f.read()
    assert content == b"ROTATED_SECRET_999\n", (
        f"Executing the vulnerable script with exploit.job did not rotate the token: {content!r}"
    )


def test_master_token_overwritten():
    assert os.path.isfile(TOKEN_PATH), f"Token file {TOKEN_PATH} does not exist."
    with open(TOKEN_PATH, "r") as f:
        content = f.read()
    assert content == "ROTATED_SECRET_999\n", f"Token file content is incorrect: {repr(content)}"


def test_secure_script_exists_and_executable():
    assert os.path.isfile(SECURE_SCRIPT), f"Secure script {SECURE_SCRIPT} does not exist."
    st = os.stat(SECURE_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Secure script {SECURE_SCRIPT} is not executable."


def test_secure_script_sanitizes_filename_and_retains_rotation_functionality():
    # Remove every input job so only verifier-generated, unpredictable cases run.
    for name in os.listdir(UPLOAD_DIR):
        path = os.path.join(UPLOAD_DIR, name)
        if name.endswith(".job"):
            os.remove(path)

    nonce = uuid.uuid4().hex
    cases = [
        ("../../auth_keys/test_escape.txt", b"test_content\n", "test_escape.job"),
        (f"../auth_keys/dyn.{nonce}.pem", os.urandom(31) + b"\n", f"a_{nonce}.job"),
        (f"./../auth_keys/second..{nonce}.crt", os.urandom(47), f"b_{nonce}.job"),
        (f"..//auth_keys/third.{nonce}/key.pem", b"third:" + os.urandom(19), f"c_{nonce}.job"),
        (f"client.{nonce}.pem", b"ordinary credential\n", f"d_{nonce}.job"),
    ]

    expected = []
    escaped_paths = []
    for raw_filename, payload, job_name in cases:
        sanitized = raw_filename.replace(".", "").replace("/", "")
        expected_path = os.path.join(CERTS_DIR, sanitized)
        escaped_path = os.path.abspath(os.path.join(CERTS_DIR, raw_filename))
        expected.append((expected_path, payload))

        if os.path.lexists(expected_path):
            if os.path.isdir(expected_path) and not os.path.islink(expected_path):
                pytest.fail(f"Unexpected directory blocks expected output: {expected_path}")
            os.remove(expected_path)

        if not escaped_path.startswith(os.path.abspath(CERTS_DIR) + os.sep):
            escaped_paths.append(escaped_path)
            if os.path.lexists(escaped_path):
                if os.path.isdir(escaped_path) and not os.path.islink(escaped_path):
                    pytest.fail(f"Unexpected directory at traversal destination: {escaped_path}")
                os.remove(escaped_path)

        encoded = base64.b64encode(payload).decode("ascii")
        with open(os.path.join(UPLOAD_DIR, job_name), "w") as f:
            f.write(f"{raw_filename}:{encoded}\n")

    result = subprocess.run([SECURE_SCRIPT], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Secure script execution failed: {result.stderr}"

    # Preserve the original escape assertion and also check every true resolved
    # traversal destination generated above.
    escaped_file = os.path.join(AUTH_KEYS_DIR, "test_escape.txt")
    assert not os.path.exists(escaped_file), "Vulnerability still exists: file escaped to auth_keys directory."
    for path in escaped_paths:
        assert not os.path.exists(path), f"Vulnerability still exists: output escaped to {path}."

    found = any("test_escape" in name for name in os.listdir(CERTS_DIR))
    assert found, "Sanitized file was not found in the certs directory."

    fixed_expected_path = os.path.join(CERTS_DIR, "auth_keystest_escapetxt")
    assert os.path.isfile(fixed_expected_path), f"Expected sanitized output {fixed_expected_path} was not created."

    for path, payload in expected:
        assert os.path.isfile(path), f"Exact sanitized output {path} was not created."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == payload, f"Decoded contents in {path} are incorrect."


def test_token_checksum():
    checksum_path = "/home/user/token_checksum.txt"
    assert os.path.isfile(checksum_path), f"Checksum file {checksum_path} does not exist."

    with open(TOKEN_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    with open(checksum_path, "r") as f:
        checksum_content = f.read().strip()

    expected_format = f"{actual_hash}  {TOKEN_PATH}"
    assert checksum_content == expected_format, (
        f"Checksum file content is incorrect. Expected: '{expected_format}', Got: '{checksum_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
