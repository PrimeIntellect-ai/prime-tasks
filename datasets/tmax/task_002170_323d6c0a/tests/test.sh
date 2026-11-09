#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess
import tarfile
import tempfile
import uuid

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

TARBALL = "/home/user/ssh_backup.tar.gz"
SCRIPT = "/home/user/backup/deploy_keys.py"
PRIVATE_KEY = "/home/user/new_key"
PUBLIC_KEY = "/home/user/new_key.pub"
DEPLOYED_KEY = "/var/secure_keys/new_key.pub"


def test_decrypted_files_exist_and_archive_is_authentic():
    """Verify that the backup was actually decrypted and extracted."""
    assert os.path.exists(TARBALL), "Decrypted tarball /home/user/ssh_backup.tar.gz is missing."
    assert os.path.exists(SCRIPT), "Extracted deploy_keys.py is missing from /home/user/backup/."
    assert os.path.isfile(TARBALL) and not os.path.islink(TARBALL), "Decrypted archive must be a regular file."
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), "deploy_keys.py must be a regular file."

    with tempfile.TemporaryDirectory() as td:
        expected = os.path.join(td, "expected.tar.gz")
        result = subprocess.run(
            [
                "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
                "-in", "/home/user/ssh_backup.enc",
                "-out", expected,
                "-pass", "pass:S3cr3t_B@ckup_P@ss!",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"Reference decryption failed: {result.stderr.decode(errors='replace')}"
        with open(expected, "rb") as f:
            expected_bytes = f.read()
        with open(TARBALL, "rb") as f:
            submitted_bytes = f.read()
        assert submitted_bytes == expected_bytes, "ssh_backup.tar.gz is not the correct decrypted archive."

    with tarfile.open(TARBALL, "r:gz") as archive:
        names = {name.lstrip("./") for name in archive.getnames()}
        assert "deploy_keys.py" in names, "The decrypted archive does not contain deploy_keys.py."


def test_deploy_keys_script_fixed():
    """Verify that deploy_keys.py lacks the original unsafe calls and safely handles hostile filenames."""
    with open(SCRIPT, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "os.system" not in content, "The script still contains vulnerable os.system calls."
    assert "shell=True" not in content, "The script still contains vulnerable shell=True execution."

    marker = "PWNED_" + uuid.uuid4().hex
    hostile_name = f"source;touch${{IFS}}{marker};#.pub"
    target = os.path.join("/var/secure_keys", hostile_name)

    with tempfile.TemporaryDirectory() as td:
        # The plain source makes the historical os.system command reach the injected command.
        with open(os.path.join(td, "source"), "wb") as f:
            f.write(b"decoy")
        payload = b"hostile filename copied literally\n"
        with open(os.path.join(td, hostile_name), "wb") as f:
            f.write(payload)

        if os.path.lexists(target):
            os.unlink(target)

        result = subprocess.run(
            ["python3", SCRIPT, hostile_name],
            cwd=td,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            "The repaired deployment script failed when given a valid filename containing shell metacharacters: "
            + result.stderr.decode(errors="replace")
        )
        assert not os.path.exists(os.path.join(td, marker)), "The deployment script permits command injection."
        assert os.path.isfile(target) and not os.path.islink(target), "The deployment script did not copy the requested file."
        with open(target, "rb") as f:
            assert f.read() == payload, "The deployment script did not preserve the copied file contents."

    if os.path.lexists(target):
        os.unlink(target)


def _load_private_key(data):
    try:
        return serialization.load_ssh_private_key(data, password=None)
    except (ValueError, TypeError):
        return serialization.load_pem_private_key(data, password=None)


def test_private_key_permissions_and_real_keypair():
    """Verify hardened key files and that they are a genuine matching Ed25519 keypair."""
    assert os.path.exists(PRIVATE_KEY), f"Private key not found at {PRIVATE_KEY}"

    file_stat = os.stat(PRIVATE_KEY)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o600, f"Private key permissions should be 0o600, but found {oct(permissions)}"
    assert stat.S_ISREG(os.lstat(PRIVATE_KEY).st_mode) and not os.path.islink(PRIVATE_KEY), "Private key must be a regular file."

    assert os.path.exists(PUBLIC_KEY), f"Public key not found at {PUBLIC_KEY}"
    assert stat.S_ISREG(os.lstat(PUBLIC_KEY).st_mode) and not os.path.islink(PUBLIC_KEY), "Public key must be a regular file."
    public_permissions = stat.S_IMODE(os.stat(PUBLIC_KEY).st_mode)
    assert public_permissions & 0o022 == 0, "Public key must not be group- or world-writable."

    with open(PRIVATE_KEY, "rb") as f:
        private = _load_private_key(f.read())
    assert isinstance(private, Ed25519PrivateKey), "new_key is not an Ed25519 private key."

    with open(PUBLIC_KEY, "rb") as f:
        public_line = f.read().strip()
    parts = public_line.split()
    assert len(parts) >= 2 and parts[0] == b"ssh-ed25519", "new_key.pub is not an OpenSSH Ed25519 public key."
    public = serialization.load_ssh_public_key(b" ".join(parts[:2]))
    assert isinstance(public, Ed25519PublicKey), "new_key.pub is not an Ed25519 public key."

    derived = private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    supplied = public.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    assert derived == supplied, "new_key and new_key.pub do not form a matching keypair."


def calculate_leading_zeros(pubkey_path):
    """Helper function to calculate leading zeros of the base64 public key body."""
    try:
        with open(pubkey_path, "r") as f:
            content = f.read().strip()
        parts = content.split()
        if len(parts) >= 2 and parts[0] == "ssh-ed25519":
            key_body = parts[1]
        else:
            key_body = parts[0]

        sha256_hex = hashlib.sha256(key_body.encode("ascii")).hexdigest()
        count = 0
        for char in sha256_hex:
            if char == "0":
                count += 1
            else:
                break
        return count
    except Exception:
        return 0


def test_vanity_key_metric():
    """Verify that the generated public key meets the vanity fingerprint requirement."""
    assert os.path.exists(PUBLIC_KEY), f"Public key not found at {PUBLIC_KEY}"
    metric_value = calculate_leading_zeros(PUBLIC_KEY)
    threshold = 5
    assert metric_value >= threshold, (
        f"Vanity key requirement not met. Expected >= {threshold} leading zeros in SHA256 hash, "
        f"but got {metric_value}."
    )


def test_key_deployed():
    """Verify that the new public key was deployed to the secure directory."""
    assert os.path.exists(DEPLOYED_KEY), f"Deployed key not found at {DEPLOYED_KEY}"
    assert os.path.isfile(DEPLOYED_KEY) and not os.path.islink(DEPLOYED_KEY), "Deployed key must be a regular file."
    with open(PUBLIC_KEY, "r") as f1, open(DEPLOYED_KEY, "r") as f2:
        assert f1.read() == f2.read(), "The deployed key does not match the generated public key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
