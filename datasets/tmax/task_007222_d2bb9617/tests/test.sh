#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import zipfile

import pytest

HOME = "/home/user"

EXPECTED_ROTATE_SCRIPT = b"".join([
    b"#!/bin/bash\n",
    b"if [ \"$#\" -ne 1 ]; then \n",
    b"    echo \"Usage: $0 <payload_file>\"\n",
    b"    exit 1\n",
    b"fi\n",
    b"PAYLOAD=$(cat \"$1\")\n",
    b"# Vulnerable command injection via eval\n",
    b"eval \"echo \\\"Rotating credentials for metadata: $PAYLOAD\\\" >> /home/user/rotation.log\"\n",
])


def read_regular_file(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert not os.path.islink(path), f"{path} must not be a symbolic link."
    mode = os.stat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} is not a regular file."
    with open(path, "rb") as f:
        return f.read()


def test_extracted_backup_key_exists_and_matches_archive():
    """The extracted backup key must be the key stored in the encrypted archive."""
    extracted_dir = os.path.join(HOME, "extracted")
    possible_paths = [
        os.path.join(extracted_dir, "backup_key.pem"),
        os.path.join(extracted_dir, "home", "user", "backup_key.pem"),
    ]

    found = any(os.path.exists(p) and os.path.isfile(p) for p in possible_paths)
    if not found:
        for root, dirs, files in os.walk(extracted_dir):
            if "backup_key.pem" in files:
                found = True
                break
    assert found, "The backup_key.pem file was not found in /home/user/extracted/ or its subdirectories."

    archive_path = os.path.join(HOME, "legacy_credentials.zip")
    dict_path = os.path.join(HOME, "dict.txt")
    assert os.path.isfile(archive_path), f"{archive_path} is missing."
    assert os.path.isfile(dict_path), f"{dict_path} is missing."

    with open(dict_path, "rb") as f:
        passwords = [line.strip() for line in f if line.strip()]

    archive_key = None
    with zipfile.ZipFile(archive_path) as zf:
        members = [n for n in zf.namelist() if n.rstrip("/").split("/")[-1] == "backup_key.pem"]
        assert members, "The archive does not contain backup_key.pem."
        for password in passwords:
            try:
                archive_key = zf.read(members[0], pwd=password)
                break
            except (RuntimeError, zipfile.BadZipFile):
                continue

    assert archive_key is not None, "No password from dict.txt decrypts backup_key.pem."
    assert archive_key == b"BACKUP_PRIVATE_KEY_CONTENTS\n", "The credential archive was altered."

    matching_files = []
    for root, dirs, files in os.walk(extracted_dir):
        for name in files:
            if name == "backup_key.pem":
                path = os.path.join(root, name)
                if not os.path.islink(path) and os.path.isfile(path):
                    matching_files.append(path)

    assert matching_files, "No regular extracted backup_key.pem file was found."
    assert any(read_regular_file(path) == archive_key for path in matching_files), \
        "The extracted backup_key.pem does not match the encrypted archive."


def test_certificate_chain_and_cert_info_format_and_content():
    """Validate the chain and verify the requested values were extracted from the certificate."""
    cert_path = os.path.join(HOME, "old_cert.pem")
    ca_path = os.path.join(HOME, "ca.crt")
    cert_info_path = os.path.join(HOME, "cert_info.txt")

    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", ca_path, cert_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert verify.returncode == 0, \
        f"old_cert.pem does not validate against ca.crt: {verify.stdout}{verify.stderr}"

    issuer_result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    serial_result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-serial"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )

    issuer = issuer_result.stdout.strip().split("=", 1)[-1]
    org_match = re.search(r"(?:^|,)O=([^,]+)", issuer)
    assert org_match, "The issuer organization could not be extracted from old_cert.pem."
    actual_org = org_match.group(1).replace("\\,", ",").strip()
    actual_serial = serial_result.stdout.strip().split("=", 1)[-1].lower()

    expected_org = "Global Security Inc"
    expected_serial = "01abcdef"
    assert actual_org == expected_org, "The certificate issuer organization is unexpected."
    assert actual_serial == expected_serial, "The certificate serial number is unexpected."

    assert os.path.exists(cert_info_path), f"The file {cert_info_path} does not exist."
    assert os.path.isfile(cert_info_path), f"{cert_info_path} is not a file."
    assert not os.path.islink(cert_info_path), f"{cert_info_path} must not be a symbolic link."

    with open(cert_info_path, "r") as f:
        raw = f.read()
    lines = raw.splitlines()
    nonempty_lines = [line.strip() for line in raw.strip().splitlines() if line.strip()]

    assert len(nonempty_lines) >= 2, f"{cert_info_path} must contain at least two lines."
    assert nonempty_lines[0] == expected_org, \
        f"Line 1 of {cert_info_path} is incorrect. Expected '{expected_org}', got '{nonempty_lines[0]}'."
    assert nonempty_lines[1].lower() == expected_serial, \
        f"Line 2 of {cert_info_path} is incorrect. Expected '{expected_serial}', got '{nonempty_lines[1]}'."

    assert len(lines) == 2, f"{cert_info_path} must contain exactly two lines."
    assert lines[0] == actual_org, "Line 1 must exactly match the certificate issuer organization."
    assert lines[1] == actual_serial, "Line 2 must be the certificate serial in lowercase hexadecimal."


def test_payload_executes_through_unmodified_rotation_script():
    """Re-run the submitted payload against a fresh secret using the original vulnerable script."""
    script_path = os.path.join(HOME, "rotate_service.sh")
    payload_path = os.path.join(HOME, "payload.txt")
    hidden_path = os.path.join(HOME, ".hidden_master_key")
    rotated_path = os.path.join(HOME, "rotated_master_key.txt")

    assert read_regular_file(script_path) == EXPECTED_ROTATE_SCRIPT, \
        "rotate_service.sh was modified."
    assert os.access(script_path, os.X_OK), "rotate_service.sh is not executable."
    read_regular_file(payload_path)

    fresh_secret = ("ROTATED_DYNAMIC_" + secrets.token_hex(32) + "\n").encode()
    if os.path.lexists(hidden_path):
        if os.path.isdir(hidden_path) and not os.path.islink(hidden_path):
            pytest.fail(f"{hidden_path} was replaced by a directory.")
        os.unlink(hidden_path)
    fd = os.open(hidden_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, "wb") as f:
        f.write(fresh_secret)

    if os.path.lexists(rotated_path):
        if os.path.isdir(rotated_path) and not os.path.islink(rotated_path):
            pytest.fail(f"{rotated_path} was replaced by a directory.")
        os.unlink(rotated_path)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", script_path, payload_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"rotate_service.sh failed while processing payload.txt: {result.stdout}{result.stderr}"

    assert read_regular_file(script_path) == EXPECTED_ROTATE_SCRIPT, \
        "rotate_service.sh was modified during payload execution."
    read_regular_file(payload_path)

    assert os.path.exists(rotated_path), \
        f"The file {rotated_path} does not exist. The exploit may have failed."
    assert os.path.isfile(rotated_path), f"{rotated_path} is not a file."
    assert not os.path.islink(rotated_path), f"{rotated_path} must not be a symbolic link."
    assert os.path.exists(hidden_path), f"The original hidden key {hidden_path} is missing."

    with open(hidden_path, "r") as f:
        expected_content = f.read().strip()
    with open(rotated_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, \
        f"The content of {rotated_path} does not match the hidden master key."
    assert read_regular_file(rotated_path) == fresh_secret, \
        "payload.txt did not copy the fresh hidden key during verifier execution."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
