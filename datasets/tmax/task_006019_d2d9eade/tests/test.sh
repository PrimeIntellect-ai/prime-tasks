#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import hashlib
import json
import os
import pwd
import re
import stat
import subprocess

import pytest


def run(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        **kwargs,
    )


def test_tls_certificates_exist_and_permissions():
    cert_path = "/home/user/tls/cert.pem"
    key_path = "/home/user/tls/key.pem"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} was not created."
    assert os.path.isfile(key_path), f"Private key file {key_path} was not created."

    # Check permissions of key.pem (should be exactly 0400 / -r--------)
    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions for {key_path} are incorrect. Expected 0400, got {oct(perms)}."
    assert st.st_uid == pwd.getpwnam("user").pw_uid, f"{key_path} is not owned by user."

    # Both files must be real, matching cryptographic material.
    run(["openssl", "x509", "-in", cert_path, "-noout"])
    run(["openssl", "pkey", "-in", key_path, "-noout"], input=b"")

    cert_pub_pem = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]).stdout
    cert_pub_der = run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub_pem
    ).stdout
    key_pub_der = run(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"],
        input=b"",
    ).stdout
    assert cert_pub_der == key_pub_der, "Certificate and private key do not match."

    subject = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"]).stdout
    issuer = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"]).stdout
    assert subject.replace(b"subject=", b"", 1) == issuer.replace(b"issuer=", b"", 1), "Certificate is not self-issued."
    run(["openssl", "verify", "-CAfile", cert_path, cert_path])

    dates = run(["openssl", "x509", "-in", cert_path, "-noout", "-startdate", "-enddate"]).stdout.decode().splitlines()
    not_before = datetime.datetime.strptime(dates[0].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z")
    not_after = datetime.datetime.strptime(dates[1].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z")
    lifetime = (not_after - not_before).total_seconds()
    assert 364.5 * 86400 <= lifetime <= 365.5 * 86400, "Certificate validity is not 365 days."
    now = datetime.datetime.utcnow()
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_stage2_bin_exists_permissions_and_content():
    stage2_path = "/tmp/stage2.bin"

    assert os.path.isfile(stage2_path), f"Decrypted payload file {stage2_path} was not created."

    # Check permissions of stage2.bin (should be exactly 0700 / -rwx------)
    st = os.stat(stage2_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions for {stage2_path} are incorrect. Expected 0700, got {oct(perms)}."

    # Check contents
    expected_content = b"echo 'RedTeamEvasionSuccessful'"
    with open(stage2_path, "rb") as f:
        content = f.read()

    assert content == expected_content, f"Contents of {stage2_path} do not match the expected decrypted payload."


def test_payload_hash_file():
    hash_file_path = "/home/user/payload_hash.txt"

    assert os.path.isfile(hash_file_path), f"Hash file {hash_file_path} was not created."

    expected_content = b"echo 'RedTeamEvasionSuccessful'"
    expected_hash = hashlib.sha256(expected_content).hexdigest()

    with open(hash_file_path, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Hash in {hash_file_path} is incorrect. Expected {expected_hash}, got {actual_hash}."


def test_rust_project_executes_decoder_on_derived_input():
    project = "/home/user/evasion_payload"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isdir(project), "Rust project directory was not created."
    assert os.path.isfile(manifest), "Rust project is missing Cargo.toml."

    metadata = json.loads(run([
        "cargo", "metadata", "--no-deps", "--format-version", "1",
        "--manifest-path", manifest,
    ]).stdout)
    rust_bins = [
        target for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
        and target.get("src_path", "").endswith(".rs")
        and os.path.isfile(target.get("src_path", ""))
    ]
    assert rust_bins, "Cargo project does not contain a Rust binary target."

    log_text = open("/home/user/ids_logs.txt", "r").read()
    match = re.search(r"PSK rotation complete.*?0x([0-9A-Fa-f]+)", log_text)
    assert match, "Could not derive the PSK from the supplied log."
    key = bytes.fromhex(match.group(1))
    assert len(key) == 4 and key.isascii(), "Logged PSK is not a four-character ASCII key."

    payload_path = "/home/user/encrypted_payload.b64"
    stage2_path = "/tmp/stage2.bin"
    original_payload = open(payload_path, "rb").read()
    original_plaintext = b"echo 'RedTeamEvasionSuccessful'"
    challenge_plaintext = b"dynamic-stage2-" + os.urandom(73) + b"\x00\xff\n"
    encrypted = bytes(value ^ key[index % len(key)] for index, value in enumerate(challenge_plaintext))

    try:
        with open(payload_path, "wb") as payload_file:
            payload_file.write(base64.b64encode(encrypted) + b"\n")
        if os.path.lexists(stage2_path):
            os.unlink(stage2_path)

        run(["cargo", "run", "--quiet", "--manifest-path", manifest])
        assert os.path.isfile(stage2_path), "Running the Rust project did not create /tmp/stage2.bin."
        with open(stage2_path, "rb") as staged_file:
            assert staged_file.read() == challenge_plaintext, "Rust program did not Base64-decode and XOR-decrypt the challenge payload."
        assert stat.S_IMODE(os.stat(stage2_path).st_mode) == 0o700, "Rust program did not set /tmp/stage2.bin to mode 0700."
    finally:
        with open(payload_path, "wb") as payload_file:
            payload_file.write(original_payload)
        if os.path.lexists(stage2_path):
            os.unlink(stage2_path)
        run(["cargo", "run", "--quiet", "--manifest-path", manifest])

    assert os.path.isfile(stage2_path), "Rust program did not restore the required final payload."
    with open(stage2_path, "rb") as staged_file:
        assert staged_file.read() == original_plaintext, "Rust program did not decode the supplied payload after restoration."
    assert stat.S_IMODE(os.stat(stage2_path).st_mode) == 0o700, "Restored /tmp/stage2.bin does not have mode 0700."


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
