#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import shutil
import subprocess
import tempfile
import uuid
import pytest

def test_payload_txt():
    payload_path = "/home/user/payload.txt"
    assert os.path.isfile(payload_path), f"File {payload_path} does not exist."

    with open(payload_path, "r") as f:
        payload = f.read().strip()

    assert not payload.startswith("../"), "Payload must bypass the naive '../' check."

    target_path = os.path.abspath(os.path.join("/home/user/vuln_app/uploads", payload))
    expected_path = "/home/user/vuln_app/pwned.txt"
    assert target_path == expected_path, f"Payload resolves to {target_path}, expected {expected_path}."

    # Exercise the real vulnerable script against a clean uploads directory so
    # the payload cannot rely on agent-created intermediate directories.
    app_dir = "/home/user/vuln_app"
    uploads_path = os.path.join(app_dir, "uploads")
    script_path = os.path.join(app_dir, "process_upload.sh")
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."
    assert os.path.isdir(uploads_path), f"Directory {uploads_path} does not exist."

    token = uuid.uuid4().hex
    uploads_backup = os.path.join(app_dir, f".verifier_uploads_{token}")
    pwned_backup = os.path.join(app_dir, f".verifier_pwned_{token}")
    had_pwned = os.path.lexists(expected_path)
    source_fd, source_path = tempfile.mkstemp(prefix="payload-source-", dir="/tmp")
    marker = ("verifier-payload-" + token).encode()

    try:
        os.write(source_fd, marker)
        os.close(source_fd)
        source_fd = None

        os.rename(uploads_path, uploads_backup)
        os.mkdir(uploads_path, 0o777)
        if had_pwned:
            os.rename(expected_path, pwned_backup)

        result = subprocess.run(
            [script_path, source_path, payload],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            "The payload does not successfully execute through process_upload.sh: "
            + result.stderr.decode(errors="replace")
        )
        assert os.path.isfile(expected_path), "The real copy did not create /home/user/vuln_app/pwned.txt."
        with open(expected_path, "rb") as f:
            assert f.read() == marker, "The created pwned.txt does not contain the copied input data."
    finally:
        if source_fd is not None:
            os.close(source_fd)
        if os.path.exists(source_path):
            os.unlink(source_path)
        if os.path.lexists(expected_path):
            if os.path.isdir(expected_path) and not os.path.islink(expected_path):
                shutil.rmtree(expected_path)
            else:
                os.unlink(expected_path)
        if os.path.lexists(uploads_path):
            if os.path.isdir(uploads_path) and not os.path.islink(uploads_path):
                shutil.rmtree(uploads_path)
            else:
                os.unlink(uploads_path)
        if os.path.lexists(uploads_backup):
            os.rename(uploads_backup, uploads_path)
        if had_pwned and os.path.lexists(pwned_backup):
            os.rename(pwned_backup, expected_path)

def test_redacted_txt():
    redacted_path = "/home/user/redacted.txt"
    assert os.path.isfile(redacted_path), f"File {redacted_path} does not exist."

    expected_content = (
        "User: alice, CC: XXXX-XXXX-XXXX-XXXX, Role: Admin\n"
        "User: bob, CC: XXXX-XXXX-XXXX-XXXX, Role: User\n"
        "User: charlie, CC: XXXX-XXXX-XXXX-XXXX, Role: Moderator\n"
        "User: dave, CC: XXXX-XXXX-XXXX-XXXX, Role: User\n"
    )

    with open(redacted_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), "The redacted.txt content does not match the expected redacted output."

def test_hash_txt():
    redacted_path = "/home/user/redacted.txt"
    hash_path = "/home/user/hash.txt"

    assert os.path.isfile(redacted_path), f"File {redacted_path} does not exist."
    assert os.path.isfile(hash_path), f"File {hash_path} does not exist."

    with open(redacted_path, "rb") as f:
        file_hash = hashlib.sha256(f.read()).hexdigest()

    with open(hash_path, "r") as f:
        hash_raw = f.read()
    hash_content = hash_raw.strip()

    expected_hash_line = f"{file_hash}  {redacted_path}"

    assert hash_content.startswith(file_hash), "hash.txt does not start with the correct SHA-256 hash."
    assert redacted_path in hash_content, f"hash.txt does not contain the filename {redacted_path}."
    assert hash_raw == expected_hash_line + "\n", "hash.txt is not in the exact default sha256sum output format."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
