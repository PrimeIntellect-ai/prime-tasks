#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import hashlib
import os
import subprocess
import tempfile
import uuid

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, padding, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.x509.oid import NameOID


def effective_global_value(content, keyword):
    """Return sshd's first active global value for a keyword."""
    in_global_context = True
    wanted = keyword.lower()
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        directive = parts[0].lower()
        if directive == "match":
            in_global_context = len(parts) == 2 and parts[1].lower() == "all"
            continue
        if in_global_context and directive == wanted and len(parts) >= 2:
            return parts[1].lower()
    return None


def run_hardening_case(initial):
    script_path = "/home/user/harden_ssh.sh"
    with tempfile.NamedTemporaryFile(mode="w+", delete=False) as f:
        f.write(initial)
        temp_config = f.name
    try:
        subprocess.run([script_path, temp_config], check=True)
        with open(temp_config, "r") as f:
            return f.read()
    finally:
        os.remove(temp_config)


def test_harden_ssh():
    script_path = "/home/user/harden_ssh.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    content = run_hardening_case(
        "Port 22\nPasswordAuthentication yes\nPermitRootLogin prohibit-password\n"
    )
    assert "PasswordAuthentication no" in content, "PasswordAuthentication not set to no"
    assert "PermitRootLogin no" in content, "PermitRootLogin not set to no"
    assert effective_global_value(content, "PasswordAuthentication") == "no"
    assert effective_global_value(content, "PermitRootLogin") == "no"

    # Appending the desired strings does not override earlier sshd settings because
    # sshd uses the first obtained value for these directives.
    content = run_hardening_case(
        "PasswordAuthentication yes\n"
        "PasswordAuthentication no\n"
        "PermitRootLogin yes\n"
        "PermitRootLogin no\n"
    )
    assert effective_global_value(content, "PasswordAuthentication") == "no"
    assert effective_global_value(content, "PermitRootLogin") == "no"

    # Settings appended inside a Match block are not global settings.
    content = run_hardening_case(
        "Port 22\n"
        "# PasswordAuthentication yes\n"
        "Match User deploy\n"
        "    PasswordAuthentication yes\n"
        "    PermitRootLogin yes\n"
    )
    assert effective_global_value(content, "PasswordAuthentication") == "no"
    assert effective_global_value(content, "PermitRootLogin") == "no"


def compile_program():
    cpp_path = "/home/user/process_payload.cpp"
    assert os.path.isfile(cpp_path), f"Missing C++ file: {cpp_path}"
    exe_path = "/home/user/process_payload"
    compile_cmd = ["g++", "-O2", cpp_path, "-o", exe_path, "-lcrypto", "-lssl"]
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert res.returncode == 0, f"Compilation failed:\n{res.stderr}"
    assert os.path.isfile(exe_path)
    return exe_path


def read_plan():
    out_file = "/home/user/rotation_plan.txt"
    assert os.path.isfile(out_file), f"Output file not created: {out_file}"
    with open(out_file, "r") as f:
        return f.read().strip()


def run_program(exe_path, passphrase, payload_path):
    out_file = "/home/user/rotation_plan.txt"
    if os.path.exists(out_file):
        os.remove(out_file)
    res = subprocess.run(
        [exe_path, passphrase, payload_path], capture_output=True, text=True
    )
    assert res.returncode == 0, f"Execution failed:\n{res.stderr}"
    return read_plan()


def make_ca(common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.datetime.utcnow()
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    return key, cert


def make_leaf(common_name, issuer_key, issuer_cert):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.datetime.utcnow()
    return (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer_cert.subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(issuer_key, hashes.SHA256())
    )


def encrypt_payload(path, passphrase, plaintext):
    key = hashlib.sha256(passphrase.encode()).digest()
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ciphertext = encryptor.update(padded) + encryptor.finalize()
    with open(path, "wb") as f:
        f.write(base64.b64encode(iv + ciphertext))


def test_process_payload():
    exe_path = compile_program()

    # Preserve and strengthen the original held-out payload assertions.
    content = run_program(
        exe_path,
        "secure rotate alpha seven seven",
        "/app/hidden_test_payload.enc",
    )
    assert "Allowed Subnet: 10.99.0.0/16" in content, "Incorrect or missing subnet in output"
    assert "Valid Certificates:" in content, "Missing 'Valid Certificates:' header"
    lines = content.splitlines()
    assert lines[0] == "Allowed Subnet: 10.99.0.0/16"
    assert lines[1] == "Valid Certificates:"
    assert len(lines) == 3, "The validating Root CA certificate subject was not emitted"
    assert "RootCA" in lines[2], "Incorrect certificate subject"

    # Exercise decryption and trust validation with values generated by the verifier.
    token = uuid.uuid4().hex
    valid_name = "valid-" + token
    invalid_name = "invalid-" + token
    passphrase = "held-out-" + uuid.uuid4().hex
    subnet = f"172.{int(token[:2], 16) % 200 + 1}.{int(token[2:4], 16)}.0/24"

    trusted_key, trusted_ca = make_ca("test-root-" + token)
    other_key, other_ca = make_ca("other-root-" + token)
    valid_cert = make_leaf(valid_name, trusted_key, trusted_ca)
    invalid_cert = make_leaf(invalid_name, other_key, other_ca)

    trusted_pem = trusted_ca.public_bytes(serialization.Encoding.PEM)
    valid_pem = valid_cert.public_bytes(serialization.Encoding.PEM)
    invalid_pem = invalid_cert.public_bytes(serialization.Encoding.PEM)
    certs = [valid_pem, invalid_pem]
    if int(token[-1], 16) % 2:
        certs.reverse()
    plaintext = subnet.encode() + b"\n" + b"".join(certs)

    root_path = "/app/root_ca.pem"
    with open(root_path, "rb") as f:
        original_root = f.read()
    try:
        with open(root_path, "wb") as f:
            f.write(trusted_pem)
        with tempfile.NamedTemporaryFile(delete=False) as payload_file:
            payload_path = payload_file.name
        try:
            encrypt_payload(payload_path, passphrase, plaintext)
            generated_content = run_program(exe_path, passphrase, payload_path)
        finally:
            os.remove(payload_path)
    finally:
        with open(root_path, "wb") as f:
            f.write(original_root)

    generated_lines = generated_content.splitlines()
    assert generated_lines[0] == "Allowed Subnet: " + subnet
    assert generated_lines[1] == "Valid Certificates:"
    assert len(generated_lines) == 3, "Output must contain exactly the one trusted certificate"
    assert valid_name in generated_lines[2], "Trusted certificate subject missing"
    assert invalid_name not in generated_content, "Untrusted certificate was reported as valid"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
