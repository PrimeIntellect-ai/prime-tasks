#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import secrets
import subprocess

import pytest
import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

URL = "http://127.0.0.1:8080/inspect"
TOKEN = "omega7delta"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def make_dummy_cert(domain: str) -> str:
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", "/dev/null", "-out", "/dev/stdout",
        "-sha256", "-days", "1", "-nodes",
        "-subj", f"/CN={domain}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, stderr=subprocess.DEVNULL)
    return result.stdout


def random_domain(label="host"):
    return f"{label}-{secrets.token_hex(6)}.example.test"


def make_cert(cn: str, sans=None) -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    now = datetime.datetime.utcnow()
    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
    )
    if sans is not None:
        builder = builder.add_extension(
            x509.SubjectAlternativeName([x509.DNSName(name) for name in sans]),
            critical=False,
        )
    cert = builder.sign(private_key=key, algorithm=hashes.SHA256())
    return cert.public_bytes(serialization.Encoding.PEM).decode("ascii")


def post(payload, headers=HEADERS):
    return requests.post(URL, headers=headers, json=payload, timeout=5)


def assert_response(payload, expected_status, expected_redacted=None):
    r = post(payload)
    assert r.status_code == 200, f"Expected 200 OK, got {r.status_code}: {r.text}"
    data = r.json()
    assert data.get("status") == expected_status, data
    if expected_redacted is not None:
        assert data.get("redacted_payload") == expected_redacted, data
    return data


def test_go_artifact_exists_and_builds():
    path = "/home/user/inspector.go"
    assert os.path.isfile(path), f"Missing Go source file: {path}"
    assert os.path.getsize(path) > 0, f"Go source file is empty: {path}"
    result = subprocess.run(
        ["go", "build", "-o", "/tmp/inspector-verifier-build", path],
        capture_output=True,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, f"inspector.go does not build:\n{result.stderr}"


def test_unauthorized():
    try:
        r = requests.post(URL, json={})
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not listening on 127.0.0.1:8080")

    assert r.status_code == 401, f"Expected 401 Unauthorized, got {r.status_code}"

    r2 = requests.post(URL, headers={"Authorization": "Bearer wrongtoken"}, json={})
    assert r2.status_code == 401, f"Expected 401 Unauthorized for wrong token, got {r2.status_code}"


def test_blocked_domain():
    cert = make_dummy_cert("evilcorp.local")
    payload = {
        "domain": "evilcorp.local",
        "cert_chain_pem": cert,
        "payload": "normal payload",
        "user_agent": "Mozilla/5.0"
    }
    r = requests.post(URL, headers=HEADERS, json=payload)
    assert r.status_code == 200, f"Expected 200 OK, got {r.status_code}"

    data = r.json()
    assert data.get("status") == "blocked_domain", f"Expected status 'blocked_domain', got {data.get('status')}"


def test_invalid_cert():
    cert = make_dummy_cert("wrongsite.com")
    payload = {
        "domain": "goodsite.com",
        "cert_chain_pem": cert,
        "payload": "normal payload",
        "user_agent": "Mozilla/5.0"
    }
    r = requests.post(URL, headers=HEADERS, json=payload)
    assert r.status_code == 200, f"Expected 200 OK, got {r.status_code}"

    data = r.json()
    assert data.get("status") == "invalid_cert", f"Expected status 'invalid_cert', got {data.get('status')}"


def test_blocked_injection():
    cert = make_dummy_cert("goodsite.com")
    payload = {
        "domain": "goodsite.com",
        "cert_chain_pem": cert,
        "payload": "normal payload",
        "user_agent": "Mozilla/5.0 ' OR 1=1 --"
    }
    r = requests.post(URL, headers=HEADERS, json=payload)
    assert r.status_code == 200, f"Expected 200 OK, got {r.status_code}"

    data = r.json()
    assert data.get("status") == "blocked_injection", f"Expected status 'blocked_injection', got {data.get('status')}"


def test_allowed_and_redaction():
    cert = make_dummy_cert("goodsite.com")
    payload = {
        "domain": "goodsite.com",
        "cert_chain_pem": cert,
        "payload": "Payment 1234567812345678 received and another 9876543210987654.",
        "user_agent": "Mozilla/5.0"
    }
    r = requests.post(URL, headers=HEADERS, json=payload)
    assert r.status_code == 200, f"Expected 200 OK, got {r.status_code}"

    data = r.json()
    assert data.get("status") == "allowed", f"Expected status 'allowed', got {data.get('status')}"
    assert data.get("redacted_payload") == "Payment XXXX-XXXX-XXXX-XXXX received and another XXXX-XXXX-XXXX-XXXX.", \
        f"Payload redaction failed, got: {data.get('redacted_payload')}"


def test_random_cn_hostname_and_general_redaction():
    domain = random_domain("cn")
    numbers = ["".join(random.choice("0123456789") for _ in range(16)) for _ in range(3)]
    original = f"ref={secrets.token_hex(5)} cards {numbers[0]}/{numbers[1]} and {numbers[2]} done"
    expected = re.sub(r"\d{16}", "XXXX-XXXX-XXXX-XXXX", original)
    assert_response({
        "domain": domain,
        "cert_chain_pem": make_cert(domain),
        "payload": original,
        "user_agent": f"VerifierClient/{secrets.randbelow(9000) + 1000}",
    }, "allowed", expected)


def test_random_san_hostname_and_leaf_first_chain():
    domain = random_domain("san")
    unrelated_cn = random_domain("cn-other")
    trailing = make_cert(random_domain("root"))
    chain = make_cert(unrelated_cn, sans=[domain]) + trailing
    marker = f"unchanged-{secrets.token_hex(10)}"
    assert_response({
        "domain": domain,
        "cert_chain_pem": chain,
        "payload": marker,
        "user_agent": f"agent-{secrets.token_hex(4)}",
    }, "allowed", marker)


def test_random_certificate_mismatch_and_malformed_certificate():
    requested = random_domain("requested")
    certified = random_domain("certified")
    assert_response({
        "domain": requested,
        "cert_chain_pem": make_cert(certified),
        "payload": secrets.token_hex(12),
        "user_agent": "dynamic-agent",
    }, "invalid_cert")

    malformed_domain = random_domain("malformed")
    assert_response({
        "domain": malformed_domain,
        "cert_chain_pem": "-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----\n",
        "payload": "ordinary",
        "user_agent": "dynamic-agent",
    }, "invalid_cert")


def test_script_detection_on_random_authenticated_request():
    domain = random_domain("script")
    ua = f"prefix-{secrets.token_hex(5)}<script>suffix-{secrets.token_hex(5)}"
    assert_response({
        "domain": domain,
        "cert_chain_pem": make_cert(domain),
        "payload": "ordinary payload",
        "user_agent": ua,
    }, "blocked_injection")


def test_exact_blocked_domain_and_precedence_combinations():
    near_domain = f"sub-{secrets.token_hex(4)}.evilcorp.local"
    assert_response({
        "domain": near_domain,
        "cert_chain_pem": make_cert(near_domain),
        "payload": "ordinary",
        "user_agent": f"normal-{secrets.token_hex(4)}",
    }, "allowed", "ordinary")

    assert_response({
        "domain": "evilcorp.local",
        "cert_chain_pem": "not pem at all",
        "payload": "ordinary",
        "user_agent": "<script>' OR 1=1",
    }, "blocked_domain")

    requested = random_domain("precedence")
    assert_response({
        "domain": requested,
        "cert_chain_pem": make_cert(random_domain("wrong")),
        "payload": "ordinary",
        "user_agent": f"x-{secrets.token_hex(3)}<script>",
    }, "invalid_cert")


def test_dynamic_wrong_authentication_is_rejected():
    wrong = secrets.token_hex(16)
    r = post({
        "domain": random_domain("auth"),
        "cert_chain_pem": "",
        "payload": "",
        "user_agent": "",
    }, headers={"Authorization": f"Bearer {wrong}"})
    assert r.status_code == 401, f"Expected 401 for dynamic wrong token, got {r.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
