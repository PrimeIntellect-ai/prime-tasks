#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import stat
import subprocess
import tempfile

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


def run(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        **kwargs,
    )


def trusted_private_key_bytes():
    with open("/home/user/ssh_key_b64.txt", "rb") as f:
        return base64.decodebytes(f.read())


def trusted_symmetric_key():
    with tempfile.TemporaryDirectory() as directory:
        key_path = os.path.join(directory, "id_rsa")
        with open(key_path, "wb") as f:
            f.write(trusted_private_key_bytes())
        os.chmod(key_path, 0o600)

        run([
            "ssh-keygen", "-p", "-q", "-P", "", "-N", "",
            "-m", "PEM", "-f", key_path,
        ])
        return run([
            "openssl", "pkeyutl", "-decrypt",
            "-inkey", key_path,
            "-in", "/home/user/sym.key.enc",
        ]).stdout


def test_cert_status():
    path = "/home/user/cert_status.txt"
    assert os.path.isfile(path), f"File not found: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "VALID", f"Expected cert_status.txt to contain 'VALID', but got '{content}'"

    result = subprocess.run(
        ["openssl", "verify", "-CAfile", "/home/user/ca.crt", "/home/user/server.crt"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, "server.crt is not validly signed by ca.crt"


def test_ssh_key_permissions():
    path = "/home/user/.ssh/id_rsa"
    assert os.path.isfile(path), f"File not found: {path}"

    file_stat = os.stat(path)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o600, f"Expected permissions 0600 for {path}, but got {oct(permissions)}"

    with tempfile.TemporaryDirectory() as directory:
        expected_path = os.path.join(directory, "expected_id_rsa")
        with open(expected_path, "wb") as f:
            f.write(trusted_private_key_bytes())
        os.chmod(expected_path, 0o600)
        expected_public = run(["ssh-keygen", "-y", "-f", expected_path]).stdout

    actual_public = run(["ssh-keygen", "-y", "-f", path]).stdout
    assert actual_public == expected_public, "id_rsa is not the private key encoded in ssh_key_b64.txt"


def test_sym_key():
    path = "/home/user/sym.key"
    assert os.path.isfile(path), f"File not found: {path}"

    size = os.path.getsize(path)
    assert size == 32, f"Expected sym.key to be exactly 32 bytes, but got {size} bytes"

    with open(path, "rb") as f:
        actual = f.read()
    expected = trusted_symmetric_key()
    assert actual == expected, "sym.key is not the RSA-decrypted contents of sym.key.enc"


def test_decrypt_traffic_script_exists():
    path = "/home/user/decrypt_traffic.py"
    assert os.path.isfile(path), f"File not found: {path}"


def test_decrypt_traffic_script_executes_on_fresh_input():
    script_path = "/home/user/decrypt_traffic.py"
    iv_path = "/home/user/iv.bin"
    traffic_path = "/home/user/traffic.enc"
    output_path = "/home/user/decrypted_payload.txt"

    with open(iv_path, "rb") as f:
        original_iv = f.read()
    with open(traffic_path, "rb") as f:
        original_traffic = f.read()

    key = trusted_symmetric_key()
    test_iv = os.urandom(16)
    test_plaintext = ("VERIFIER_DYNAMIC_PAYLOAD_" + os.urandom(24).hex()).encode("ascii")
    padder = padding.PKCS7(128).padder()
    padded = padder.update(test_plaintext) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(test_iv)).encryptor()
    test_ciphertext = encryptor.update(padded) + encryptor.finalize()

    try:
        with open(iv_path, "wb") as f:
            f.write(test_iv)
        with open(traffic_path, "wb") as f:
            f.write(test_ciphertext)
        if os.path.exists(output_path):
            os.remove(output_path)

        run(["python3", script_path], cwd="/home/user")
        assert os.path.isfile(output_path), "decrypt_traffic.py did not create decrypted_payload.txt"
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == test_plaintext, "decrypt_traffic.py failed to decrypt a fresh AES-256-CBC payload"
    finally:
        with open(iv_path, "wb") as f:
            f.write(original_iv)
        with open(traffic_path, "wb") as f:
            f.write(original_traffic)
        if os.path.exists(output_path):
            os.remove(output_path)
        run(["python3", script_path], cwd="/home/user")


def test_decrypted_payload():
    path = "/home/user/decrypted_payload.txt"
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, "r") as f:
        content = f.read()

    expected = "CRITICAL_PAYLOAD_DATA_XYZ_12345"
    assert content == expected, f"Expected decrypted payload to be '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
