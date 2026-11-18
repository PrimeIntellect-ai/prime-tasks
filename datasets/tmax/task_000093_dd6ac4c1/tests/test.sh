#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import stat
import subprocess


def run_command(args, input_data=None):
    return subprocess.run(args, input=input_data, capture_output=True, check=False)


def test_phase1_tls_certificates():
    cert_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"

    assert os.path.isfile(cert_path), f"Certificate file missing at {cert_path}"
    assert os.path.isfile(key_path), f"Key file missing at {key_path}"

    # Check permissions of the key
    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Expected {key_path} to have 600 permissions, got {oct(perms)}"

    # Check Common Name using openssl
    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to parse certificate with openssl"
    # The output format can vary, but typically contains CN = staging.local or CN=staging.local
    assert "CN = staging.local" in result.stdout or "CN=staging.local" in result.stdout, \
        f"Certificate does not have the correct Common Name. Subject: {result.stdout}"

    # Check that the certificate contains an RSA 2048-bit public key.
    cert_text = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"],
        capture_output=True, text=True
    )
    assert cert_text.returncode == 0, f"Could not inspect certificate: {cert_text.stderr}"
    assert "Public Key Algorithm: rsaEncryption" in cert_text.stdout, \
        "Certificate public key is not RSA"
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text.stdout), \
        "Certificate RSA key is not 2048 bits"

    # Ensure the key is a readable private key and matches the certificate.
    cert_pem_pub = run_command(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    assert cert_pem_pub.returncode == 0, cert_pem_pub.stderr.decode(errors="replace")
    cert_der_pub = run_command(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], cert_pem_pub.stdout
    )
    assert cert_der_pub.returncode == 0, cert_der_pub.stderr.decode(errors="replace")

    key_der_pub = run_command(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]
    )
    assert key_der_pub.returncode == 0, \
        f"Private key is not readable by OpenSSL: {key_der_pub.stderr.decode(errors='replace')}"
    assert cert_der_pub.stdout == key_der_pub.stdout, \
        "server.key does not match the public key in server.crt"

    # A self-signed certificate must name itself as issuer and verify using itself.
    identity = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"],
        capture_output=True, text=True
    )
    assert identity.returncode == 0, f"Could not inspect certificate identity: {identity.stderr}"
    identity_lines = [line.strip() for line in identity.stdout.splitlines() if line.strip()]
    assert len(identity_lines) == 2, f"Unexpected subject/issuer output: {identity.stdout}"
    subject = identity_lines[0].split("=", 1)[1]
    issuer = identity_lines[1].split("=", 1)[1]
    assert subject == issuer, "Certificate issuer and subject differ; it is not self-signed"

    verification = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        capture_output=True, text=True
    )
    assert verification.returncode == 0, \
        f"Certificate does not verify as self-signed: {verification.stdout}{verification.stderr}"


def test_phase2_file_permissions():
    web_root = "/home/user/web_root"
    assert os.path.isdir(web_root), f"Directory missing: {web_root}"

    for root, dirs, files in os.walk(web_root):
        # Check current directory
        st_dir = os.stat(root)
        dir_perms = stat.S_IMODE(st_dir.st_mode)
        assert dir_perms == 0o755, f"Directory {root} should have 755 permissions, got {oct(dir_perms)}"

        # Check files
        for f in files:
            file_path = os.path.join(root, f)
            st_file = os.stat(file_path)
            file_perms = stat.S_IMODE(st_file.st_mode)
            assert file_perms == 0o644, f"File {file_path} should have 644 permissions, got {oct(file_perms)}"


def test_phase3_csp_enforcement():
    index_path = "/home/user/web_root/index.html"
    assert os.path.isfile(index_path), f"File missing: {index_path}"

    with open(index_path, "r") as f:
        content = f.read()

    expected_csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self';\">"
    assert expected_csp in content, "CSP meta tag is missing or incorrect in index.html"

    # Check if it is immediately after <head>
    # Find <head> and check what follows
    head_idx = content.find("<head>")
    assert head_idx != -1, "<head> tag missing in index.html"

    after_head = content[head_idx + len("<head>"):].strip()
    assert after_head.startswith(expected_csp), "CSP meta tag is not immediately after the <head> tag"


def test_phase4_sensitive_data_redaction():
    script_path = "/home/user/redact.sh"
    source_log_path = "/home/user/logs/app.log"
    redacted_log_path = "/home/user/logs/app_redacted.log"

    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"

    assert os.path.isfile(redacted_log_path), f"Redacted log missing: {redacted_log_path}"

    with open(redacted_log_path, "r") as f:
        content = f.read()

    assert "XXXX-XXXX-XXXX-4444" in content, "First credit card was not correctly redacted"
    assert "XXXX-XXXX-XXXX-8888" in content, "Second credit card was not correctly redacted"

    assert "4111-2222-3333-4444" not in content, "Original first credit card is still present in redacted log"
    assert "5555-6666-7777-8888" not in content, "Original second credit card is still present in redacted log"

    # Exercise the submitted executable on unpredictable card numbers rather than
    # trusting a pre-fabricated output for the two setup values.
    with open(source_log_path, "rb") as f:
        original_source = f.read()
    with open(redacted_log_path, "rb") as f:
        original_redacted = f.read()

    cards = []
    for _ in range(3):
        groups = [f"{secrets.randbelow(10000):04d}" for _ in range(4)]
        cards.append("-".join(groups))

    test_input = (
        f"[TEST] first={cards[0]}\n"
        f"two cards: {cards[1]} and {cards[2]}\n"
        "leave these unchanged: 1234-5678-9012 and XXXX-XXXX-XXXX-9999\n"
        "ordinary text must also survive exactly\n"
    )
    expected = re.sub(
        r"(?<![0-9])([0-9]{4})-([0-9]{4})-([0-9]{4})-([0-9]{4})(?![0-9])",
        lambda match: "XXXX-XXXX-XXXX-" + match.group(4),
        test_input,
    )

    try:
        with open(source_log_path, "w") as f:
            f.write(test_input)

        executed = subprocess.run([script_path], capture_output=True, text=True, timeout=15)
        assert executed.returncode == 0, \
            f"redact.sh failed when executed: stdout={executed.stdout!r}, stderr={executed.stderr!r}"
        assert os.path.isfile(redacted_log_path), \
            "redact.sh did not create /home/user/logs/app_redacted.log"

        with open(redacted_log_path, "r") as f:
            actual = f.read()
        assert actual == expected, \
            f"redact.sh did not generally redact the supplied log. Expected {expected!r}, got {actual!r}"
        for card in cards:
            assert card not in actual, f"Unredacted generated card remains in output: {card}"
    finally:
        with open(source_log_path, "wb") as f:
            f.write(original_source)
        with open(redacted_log_path, "wb") as f:
            f.write(original_redacted)


def test_phase5_audit_summary():
    summary_path = "/home/user/audit_summary.txt"
    cert_path = "/home/user/certs/server.crt"

    assert os.path.isfile(summary_path), f"Summary file missing: {summary_path}"

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    assert len(lines) == 4, f"Expected exactly 4 lines in {summary_path}, got {len(lines)}"

    # Line 1: MD5 hash of server.crt
    if os.path.isfile(cert_path):
        with open(cert_path, "rb") as cf:
            expected_md5 = hashlib.md5(cf.read()).hexdigest()
    else:
        expected_md5 = "CERT_MISSING"

    assert lines[0] == expected_md5, f"Line 1 expected MD5 {expected_md5}, got {lines[0]}"

    # Line 2: Permissions of index.html
    assert lines[1] == "644", f"Line 2 expected '644', got {lines[1]}"

    # Line 3: Number of redacted lines
    assert lines[2] == "2", f"Line 3 expected '2', got {lines[2]}"

    # Line 4: AUDIT_COMPLETE
    assert lines[3] == "AUDIT_COMPLETE", f"Line 4 expected 'AUDIT_COMPLETE', got {lines[3]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
