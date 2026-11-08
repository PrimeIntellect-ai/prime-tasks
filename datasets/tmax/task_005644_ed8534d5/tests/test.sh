#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import subprocess

DUMP = "/home/user/dump.hex"
IP_FILE = "/home/user/attacker_ip.txt"
SOURCE = "/home/user/decrypt.c"
BINARY = "/home/user/decrypt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10, **kwargs)


def test_attacker_ip_extracted():
    assert os.path.isfile(IP_FILE), f"File not found: {IP_FILE}"
    with open(IP_FILE, "r") as f:
        content = f.read().strip()
    assert content == "192.168.137.42", \
        f"Expected IP '192.168.137.42', but found '{content}' in {IP_FILE}"


def test_c_program_exists_and_compiled():
    assert os.path.isfile(SOURCE), f"C source file not found: {SOURCE}"
    with open(SOURCE, "r") as f:
        c_code = f.read()
    assert "main" in c_code, \
        f"C source file {SOURCE} does not appear to contain a main function"

    assert os.path.isfile(BINARY), f"Compiled binary not found: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled binary is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled binary is not an ELF executable: {BINARY}"


def make_case():
    while True:
        octets = [secrets.randbelow(223) + 1 for _ in range(4)]
        ip = ".".join(str(x) for x in octets)
        plaintext = f"ALERT MALWARE traffic from {ip} blocked".encode("ascii")
        key = secrets.randbelow(255) + 1
        encrypted = bytes(byte ^ key for byte in plaintext)
        candidates = []
        for candidate_key in range(256):
            decoded = bytes(byte ^ candidate_key for byte in encrypted)
            if b"MALWARE" in decoded:
                candidates.append(candidate_key)
        if candidates == [key]:
            return encrypted.hex().upper(), ip


def exercise(executable, count):
    for _ in range(count):
        encoded, expected_ip = make_case()
        with open(DUMP, "w") as f:
            f.write(encoded + "\n")
        try:
            os.remove(IP_FILE)
        except FileNotFoundError:
            pass
        result = run([executable])
        assert result.returncode == 0, \
            f"{executable} failed on a valid encrypted payload:\n{result.stderr}"
        assert os.path.isfile(IP_FILE), f"{executable} did not create {IP_FILE}"
        with open(IP_FILE, "r") as f:
            actual = f.read().strip()
        assert actual == expected_ip, \
            f"{executable} extracted '{actual}', expected '{expected_ip}'"


def test_program_actually_decodes_bruteforces_and_extracts():
    with open(DUMP, "rb") as f:
        original_dump = f.read()

    rebuilt = "/tmp/decrypt_from_submitted_source"
    compile_result = run(["gcc", SOURCE, "-o", rebuilt])
    assert compile_result.returncode == 0, \
        f"Submitted C source does not compile:\n{compile_result.stderr}"

    try:
        exercise(BINARY, 2)
        exercise(rebuilt, 1)
    finally:
        with open(DUMP, "wb") as f:
            f.write(original_dump)
        try:
            os.remove(IP_FILE)
        except FileNotFoundError:
            pass
        restore = run([BINARY])
        assert restore.returncode == 0, \
            f"Binary failed when restoring output for the supplied dump:\n{restore.stderr}"

    with open(IP_FILE, "r") as f:
        assert f.read().strip() == "192.168.137.42"


def test_tls_certificate_and_key():
    cert_file = "/home/user/cert.pem"
    key_file = "/home/user/key.pem"

    assert os.path.isfile(cert_file), f"Certificate file not found: {cert_file}"
    assert os.path.isfile(key_file), f"Key file not found: {key_file}"

    # Original key-validity assertion.
    key_check = run(["openssl", "rsa", "-in", key_file, "-check", "-noout"])
    assert key_check.returncode == 0, f"Invalid RSA key in {key_file}:\n{key_check.stderr}"

    # Original certificate-subject assertion.
    cert_subject = run(["openssl", "x509", "-in", cert_file, "-noout", "-subject"])
    assert cert_subject.returncode == 0, \
        f"Failed to read certificate {cert_file}:\n{cert_subject.stderr}"
    subject_output = cert_subject.stdout.strip()
    assert "CN = secure-service" in subject_output or "CN=secure-service" in subject_output, \
        f"Certificate does not have Common Name 'secure-service'. Subject found: {subject_output}"

    # Original RSA-size assertion.
    key_size_check = run(["openssl", "rsa", "-in", key_file, "-text", "-noout"])
    assert "Private-Key: (2048 bit" in key_size_check.stdout, \
        "RSA key is not 2048-bit as requested."

    # Require exactly one CN with the requested value.
    multiline_subject = run([
        "openssl", "x509", "-in", cert_file, "-noout", "-subject", "-nameopt", "multiline"
    ])
    assert multiline_subject.returncode == 0, multiline_subject.stderr
    cn_values = []
    for line in multiline_subject.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("commonName") and "=" in stripped:
            cn_values.append(stripped.split("=", 1)[1].strip())
    assert cn_values == ["secure-service"], \
        f"Expected exactly one CN equal to secure-service, found {cn_values}"

    # The certificate must contain the public key corresponding to the submitted private key.
    cert_pub = run(["openssl", "x509", "-in", cert_file, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", key_file, "-pubout"])
    assert cert_pub.returncode == 0, cert_pub.stderr
    assert key_pub.returncode == 0, key_pub.stderr
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), \
        "Certificate and private key do not match"

    # Require a genuinely self-signed certificate and verify its signature.
    names = run([
        "openssl", "x509", "-in", cert_file, "-noout", "-subject", "-issuer",
        "-nameopt", "RFC2253"
    ])
    assert names.returncode == 0, names.stderr
    name_lines = [line.strip() for line in names.stdout.splitlines() if line.strip()]
    assert len(name_lines) == 2, f"Could not read certificate subject and issuer: {names.stdout}"
    subject = name_lines[0].split("=", 1)[1]
    issuer = name_lines[1].split("=", 1)[1]
    assert subject == issuer, f"Certificate is not self-issued: subject={subject}, issuer={issuer}"

    verify = run(["openssl", "verify", "-CAfile", cert_file, cert_file])
    assert verify.returncode == 0, f"Certificate self-signature verification failed:\n{verify.stderr}"

    # A -days 365 certificate has an exact 365-day notBefore/notAfter interval.
    dates = run(["openssl", "x509", "-in", cert_file, "-noout", "-startdate", "-enddate"])
    assert dates.returncode == 0, dates.stderr
    parsed = {}
    for line in dates.stdout.splitlines():
        name, value = line.split("=", 1)
        parsed[name] = datetime.datetime.strptime(value.strip(), "%b %d %H:%M:%S %Y GMT")
    assert "notBefore" in parsed and "notAfter" in parsed, \
        f"Could not parse certificate validity: {dates.stdout}"
    assert parsed["notAfter"] - parsed["notBefore"] == datetime.timedelta(days=365), \
        "Certificate validity period is not exactly 365 days"
    now = datetime.datetime.utcnow()
    assert parsed["notBefore"] <= now <= parsed["notAfter"], \
        "Certificate is not currently valid"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
