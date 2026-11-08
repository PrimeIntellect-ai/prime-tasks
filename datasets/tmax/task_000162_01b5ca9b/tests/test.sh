#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import string
import subprocess
import urllib.parse

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

AGENT_SCRIPT = "/home/user/secure_upload.py"
ROOT_CA = "/app/root_ca.pem"
CERTS_DIR = "/app/fuzz_certs"
TOKEN_CORRECT = "a9f3b20c8d71"
N = 2000
BASE_DIR = "/var/uploads"


def cert_time(cert, modern_name, legacy_name):
    value = getattr(cert, modern_name, None)
    if value is not None:
        return value
    return getattr(cert, legacy_name).replace(tzinfo=datetime.timezone.utc)


def verify_cert(cert_path):
    try:
        with open(ROOT_CA, "rb") as f:
            ca_cert = x509.load_pem_x509_certificate(f.read())
        with open(cert_path, "rb") as f:
            client_cert = x509.load_pem_x509_certificate(f.read())

        now = datetime.datetime.now(datetime.timezone.utc)
        if now < cert_time(client_cert, "not_valid_before_utc", "not_valid_before"):
            return False
        if now > cert_time(client_cert, "not_valid_after_utc", "not_valid_after"):
            return False
        if client_cert.issuer != ca_cert.subject:
            return False

        ca_cert.public_key().verify(
            client_cert.signature,
            client_cert.tbs_certificate_bytes,
            padding.PKCS1v15(),
            client_cert.signature_hash_algorithm,
        )
        return True
    except Exception:
        return False


def temporarily_escapes(decoded_path):
    parts = decoded_path.split("/")
    if not decoded_path.startswith("/"):
        depth = 0
        for part in parts:
            if part in ("", "."):
                continue
            if part == "..":
                if depth == 0:
                    return True
                depth -= 1
            else:
                depth += 1
        return False

    base_parts = [p for p in BASE_DIR.split("/") if p]
    stack = []
    entered_base = False
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            if stack:
                stack.pop()
        else:
            stack.append(part)

        inside_base = stack[:len(base_parts)] == base_parts and len(stack) >= len(base_parts)
        if inside_base:
            entered_base = True
        elif entered_base:
            return True
    return False


def expected(path, token, cert):
    if token != TOKEN_CORRECT:
        return 1, "ERROR: INVALID_TOKEN"
    if not verify_cert(cert):
        return 2, "ERROR: INVALID_CERT"

    decoded = urllib.parse.unquote(path)
    final_path = os.path.normpath(os.path.join(BASE_DIR, decoded))
    try:
        contained = os.path.commonpath([BASE_DIR, final_path]) == BASE_DIR
    except (TypeError, ValueError):
        contained = False

    if not contained or temporarily_escapes(decoded):
        return 3, "ERROR: PATH_TRAVERSAL"
    return 0, f"SUCCESS: {final_path}"


def run_agent(path, token, cert):
    result = subprocess.run(
        ["python3", AGENT_SCRIPT, "--path", path, "--token", token, "--cert", cert],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def assert_case(path, token, cert):
    expected_code, expected_stdout = expected(path, token, cert)
    actual_code, actual_stdout, actual_stderr = run_agent(path, token, cert)
    assert actual_code == expected_code, (
        f"Exit code mismatch for path={path!r}, token={token!r}, cert={cert!r}: "
        f"expected {expected_code}, got {actual_code}; stdout={actual_stdout!r}; "
        f"stderr={actual_stderr!r}"
    )
    assert actual_stdout == expected_stdout, (
        f"Stdout mismatch for path={path!r}, token={token!r}, cert={cert!r}: "
        f"expected {expected_stdout!r}, got {actual_stdout!r}; stderr={actual_stderr!r}"
    )


def make_same_issuer_forgery(path):
    with open(ROOT_CA, "rb") as f:
        ca_cert = x509.load_pem_x509_certificate(f.read())
    attacker_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)
    forged = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Forged Client")]))
        .issuer_name(ca_cert.subject)
        .public_key(attacker_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .sign(attacker_key, hashes.SHA256())
    )
    with open(path, "wb") as f:
        f.write(forged.public_bytes(x509.Encoding.PEM) if hasattr(x509, "Encoding") else b"")


def write_forgery(path):
    from cryptography.hazmat.primitives import serialization
    with open(ROOT_CA, "rb") as f:
        ca_cert = x509.load_pem_x509_certificate(f.read())
    attacker_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)
    forged = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Forged Client")]))
        .issuer_name(ca_cert.subject)
        .public_key(attacker_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .sign(attacker_key, hashes.SHA256())
    )
    with open(path, "wb") as f:
        f.write(forged.public_bytes(serialization.Encoding.PEM))


def generate_fuzz_inputs():
    random.seed(42)
    inputs = []
    path_chars = list(string.ascii_letters + string.digits) + ["/", ".", "%", "\\"]
    traversal_sequences = [
        "../", "..%2f", "%2e%2e/", "/var/uploads/../../etc/passwd",
        "..\\", "%2e%2e%2f", ".%2e/", "%2e./"
    ]

    for _ in range(N):
        if random.random() < 0.2:
            token = TOKEN_CORRECT
        else:
            length = random.randint(1, 20)
            token = "".join(random.choices(string.ascii_letters + string.digits, k=length))

        cert = os.path.join(CERTS_DIR, f"cert_{random.randint(0, 99)}.pem")
        if random.random() < 0.5:
            prefix = "".join(random.choices(path_chars, k=random.randint(0, 20)))
            suffix = "".join(random.choices(path_chars, k=random.randint(0, 20)))
            path = prefix + random.choice(traversal_sequences) + suffix
        else:
            path = "".join(random.choices(path_chars, k=random.randint(1, 100)))
        inputs.append((path, token, cert))
    return inputs


def test_validation_behavior():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert not os.path.islink(AGENT_SCRIPT), "Agent script must be a regular submitted file"

    cert_paths = [os.path.join(CERTS_DIR, f"cert_{i}.pem") for i in range(100)]
    valid_certs = [path for path in cert_paths if verify_cert(path)]
    assert valid_certs, "Test environment contains no valid client certificate"
    valid_cert = valid_certs[0]

    forged_path = "/tmp/same_issuer_forged.pem"
    write_forgery(forged_path)
    assert not verify_cert(forged_path)

    # Check validation order and require cryptographic signature verification.
    assert_case("../outside", "wrong-token", "/does/not/exist.pem")
    assert_case("safe/file.txt", TOKEN_CORRECT, forged_path)

    # Check traversal that leaves the upload root before returning, plus a safe normalization.
    assert_case("../var/uploads/returned.txt", TOKEN_CORRECT, valid_cert)
    assert_case("a/../../a/returned.txt", TOKEN_CORRECT, valid_cert)
    assert_case("directory/../file.txt", TOKEN_CORRECT, valid_cert)

    for path, token, cert in generate_fuzz_inputs():
        assert_case(path, token, cert)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
