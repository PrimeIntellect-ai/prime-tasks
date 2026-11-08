#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import stat
import subprocess

GOBLIN_DIR = "/app/goblin-0.7.1"
SOLUTION_DIR = "/home/user/solution"
AGENT_PATH = "/home/user/solution/target/release/decoder"
ORACLE_PATH = "/opt/oracle/decoder"


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def test_stage1_goblin_builds():
    """Verify that the vendored goblin crate compiles successfully."""
    assert os.path.isdir(GOBLIN_DIR), f"Directory {GOBLIN_DIR} does not exist"
    result = run(["cargo", "build"], cwd=GOBLIN_DIR)
    assert result.returncode == 0, (
        f"cargo build failed in {GOBLIN_DIR}:\n"
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )


def test_stage2_tls_certs():
    """Verify permissions, RSA size, self-signing, and key/certificate pairing."""
    cert_dir = "/home/user/certs"
    key_path = os.path.join(cert_dir, "client.key")
    crt_path = os.path.join(cert_dir, "client.crt")

    assert os.path.isfile(key_path), f"Private key missing at {key_path}"
    assert os.path.isfile(crt_path), f"Certificate missing at {crt_path}"

    perms = stat.S_IMODE(os.stat(key_path).st_mode)
    assert perms == 0o400, f"Permissions on {key_path} are {oct(perms)}, expected 0o400"

    key_data = open(key_path, "rb").read()
    assert b"ENCRYPTED" not in key_data, "Private key must be unencrypted"

    key_check = run(["openssl", "rsa", "-in", key_path, "-check", "-noout"])
    assert key_check.returncode == 0, (
        f"Invalid or encrypted RSA key:\n{key_check.stderr.decode(errors='replace')}"
    )

    key_text = run(["openssl", "rsa", "-in", key_path, "-text", "-noout"])
    assert key_text.returncode == 0
    key_description = (key_text.stdout + key_text.stderr).decode(errors="replace")
    match = re.search(r"(?:Private-Key|RSA Private-Key): \((\d+) bit", key_description)
    assert match and int(match.group(1)) == 2048, "Private key must be exactly RSA 2048-bit"

    cert_check = run(["openssl", "x509", "-in", crt_path, "-noout", "-text"])
    assert cert_check.returncode == 0, (
        f"Invalid x509 certificate:\n{cert_check.stderr.decode(errors='replace')}"
    )
    cert_text = cert_check.stdout.decode(errors="replace")
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate key is not RSA"
    cert_bits = re.search(r"Public-Key: \((\d+) bit\)", cert_text)
    assert cert_bits and int(cert_bits.group(1)) == 2048, "Certificate must contain a 2048-bit RSA key"

    names = run([
        "openssl", "x509", "-in", crt_path, "-noout",
        "-subject", "-issuer", "-nameopt", "RFC2253"
    ])
    assert names.returncode == 0
    lines = [line.strip() for line in names.stdout.decode(errors="replace").splitlines()]
    subject = next((line.split("=", 1)[1] for line in lines if line.startswith("subject=")), None)
    issuer = next((line.split("=", 1)[1] for line in lines if line.startswith("issuer=")), None)
    assert subject is not None and issuer is not None and subject == issuer, (
        "Certificate subject and issuer differ; it is not self-signed"
    )

    verify = run(["openssl", "verify", "-CAfile", crt_path, crt_path])
    assert verify.returncode == 0, (
        f"Certificate does not verify with its own public key:\n"
        f"{verify.stderr.decode(errors='replace')}"
    )

    key_pub = run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"])
    assert key_pub.returncode == 0
    cert_pub_pem = run(["openssl", "x509", "-in", crt_path, "-pubkey", "-noout"])
    assert cert_pub_pem.returncode == 0
    cert_pub = run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_pub_pem.stdout
    )
    assert cert_pub.returncode == 0
    assert key_pub.stdout == cert_pub.stdout, "Certificate and private key do not form a pair"


def test_stage3_is_rust_project_with_local_goblin_and_release_binary():
    manifest = os.path.join(SOLUTION_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), f"Rust manifest missing at {manifest}"

    metadata_proc = run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=SOLUTION_DIR
    )
    assert metadata_proc.returncode == 0, (
        f"Invalid Rust project:\n{metadata_proc.stderr.decode(errors='replace')}"
    )
    metadata = json.loads(metadata_proc.stdout)
    manifest_real = os.path.realpath(manifest)
    packages = [
        package for package in metadata.get("packages", [])
        if os.path.realpath(package.get("manifest_path", "")) == manifest_real
    ]
    assert packages, "Cargo metadata does not contain the submitted package"

    package = packages[0]
    decoder_targets = [
        target for target in package.get("targets", [])
        if target.get("name") == "decoder" and "bin" in target.get("kind", [])
    ]
    assert decoder_targets, "The Rust project has no binary target named decoder"
    for target in decoder_targets:
        assert target.get("src_path", "").endswith(".rs"), "decoder target is not Rust source"

    goblin_dependencies = [
        dep for dep in package.get("dependencies", []) if dep.get("name") == "goblin"
    ]
    assert goblin_dependencies, "Rust project does not depend on goblin"
    expected_goblin = os.path.realpath(GOBLIN_DIR)
    assert any(
        dep.get("source") is None
        and dep.get("path") is not None
        and os.path.realpath(dep["path"]) == expected_goblin
        for dep in goblin_dependencies
    ), "goblin must be a path dependency on /app/goblin-0.7.1"

    build = run(["cargo", "build", "--release", "--bin", "decoder"], cwd=SOLUTION_DIR)
    assert build.returncode == 0, (
        f"cargo build --release failed:\n{build.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release decoder is not an ELF executable"

    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Submitted decoder is a byte-identical oracle copy"


def assert_decoder(input_bytes, expected_code, expected_stdout):
    proc = run([AGENT_PATH], input=input_bytes)
    assert proc.returncode == expected_code, (
        f"Wrong exit code for input {input_bytes!r}: expected {expected_code}, "
        f"got {proc.returncode}; stderr={proc.stderr!r}"
    )
    assert proc.stdout == expected_stdout, (
        f"Wrong stdout for input {input_bytes!r}: expected {expected_stdout!r}, "
        f"got {proc.stdout!r}"
    )


def test_stage3_required_edge_behaviors():
    invalid = b"INVALID_ELF\n"

    # EOF, empty input, and valid Base64 decoding to fewer than four bytes.
    for data in [b"", b"\n", b"QQ==\n", b"QUI=\n", b"QUJD\n"]:
        assert_decoder(data, 1, invalid)

    # Invalid Standard Base64: invalid alphabet, bad length, misplaced/excess
    # padding, trailing data, and embedded whitespace.
    for data in [
        b"!!!!\n", b"abc\n", b"A===\n", b"====\n", b"AA=A\n",
        b"AAAA=\n", b"AA==junk\n", b"AA A=\n", b"AAAA\t\n", b"@@@=\n"
    ]:
        assert_decoder(data, 1, invalid)

    # Correctly decoded data with the wrong magic is invalid.
    assert_decoder(base64.b64encode(b"NOPEpayload") + b"\n", 1, invalid)

    # A valid payload must be emitted byte-for-byte, including arbitrary bytes.
    payload = b"\x7fELF\x00\xff\n\rpayload"
    encoded = bytes(byte ^ 0x5A for byte in payload)
    assert_decoder(base64.b64encode(encoded) + b"\n", 0, payload)
    assert_decoder(base64.b64encode(encoded) + b"\r\n", 0, payload)

    # Only the first input line is read.
    assert_decoder(base64.b64encode(encoded) + b"\nnot-base64\n", 0, payload)


def test_stage3_decoder_fuzz_equivalence():
    """Preserve the original 10,000-case oracle equivalence test."""
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"

    random.seed(42)
    for i in range(10000):
        length = random.randint(4, 1024)
        raw_bytes = bytearray(random.getrandbits(8) for _ in range(length))

        if i % 2 == 1:
            raw_bytes[0] = 0x7F ^ 0x5A
            raw_bytes[1] = 0x45 ^ 0x5A
            raw_bytes[2] = 0x4C ^ 0x5A
            raw_bytes[3] = 0x46 ^ 0x5A

        b64_input = base64.b64encode(raw_bytes) + b"\n"
        oracle_proc = run([ORACLE_PATH], input=b64_input)
        agent_proc = run([AGENT_PATH], input=b64_input)

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Exit code mismatch on iteration {i}.\n"
            f"Input (base64): {b64_input.decode().strip()}\n"
            f"Oracle exit code: {oracle_proc.returncode}\n"
            f"Agent exit code: {agent_proc.returncode}"
        )
        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Stdout mismatch on iteration {i}.\n"
            f"Input (base64): {b64_input.decode().strip()}\n"
            f"Oracle stdout length: {len(oracle_proc.stdout)}\n"
            f"Agent stdout length: {len(agent_proc.stdout)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
