#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

EXPECTED_FILES = [
    "/home/user/old_pub.pem",
    "/home/user/new_key.pem",
    "/home/user/new_cert.pem",
    "/home/user/new_pub.pem",
    "/home/user/jwt_filter.py",
]


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_jwt(payload, key=None, alg="RS256"):
    header = {"typ": "JWT", "alg": alg}
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = (h + "." + p).encode("ascii")
    if key is None:
        signature = b""
    else:
        signature = key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    return h + "." + p + "." + b64url(signature)


def public_der(key):
    if hasattr(key, "public_key"):
        key = key.public_key()
    return key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def test_required_files_and_key_material():
    for path in EXPECTED_FILES:
        assert os.path.isfile(path), "Expected file missing: " + path

    binary = open("/app/bin/legacy_auth_service", "rb").read()
    match = re.search(
        rb"-----BEGIN PUBLIC KEY-----\n.*?-----END PUBLIC KEY-----\n?",
        binary,
        re.DOTALL,
    )
    assert match, "No embedded PEM public key found in legacy binary"
    embedded_pem = match.group(0)
    if not embedded_pem.endswith(b"\n"):
        embedded_pem += b"\n"

    old_pem = open("/home/user/old_pub.pem", "rb").read()
    assert old_pem == embedded_pem, "old_pub.pem is not the exact embedded PEM"
    old_public = serialization.load_pem_public_key(old_pem)
    assert isinstance(old_public, rsa.RSAPublicKey)
    assert old_public.key_size == 2048

    new_private = serialization.load_pem_private_key(
        open("/home/user/new_key.pem", "rb").read(), password=None
    )
    new_public = serialization.load_pem_public_key(
        open("/home/user/new_pub.pem", "rb").read()
    )
    assert isinstance(new_private, rsa.RSAPrivateKey)
    assert new_private.key_size == 2048
    assert public_der(new_private) == public_der(new_public)

    cert = x509.load_pem_x509_certificate(open("/home/user/new_cert.pem", "rb").read())
    assert cert.issuer == cert.subject, "Certificate is not self-signed"
    assert cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value == "auth.local"
    assert public_der(cert.public_key()) == public_der(new_public)
    cert.public_key().verify(
        cert.signature,
        cert.tbs_certificate_bytes,
        padding.PKCS1v15(),
        cert.signature_hash_algorithm,
    )

    not_before = getattr(cert, "not_valid_before_utc", cert.not_valid_before.replace(tzinfo=datetime.timezone.utc))
    not_after = getattr(cert, "not_valid_after_utc", cert.not_valid_after.replace(tzinfo=datetime.timezone.utc))
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after
    duration = not_after - not_before
    assert datetime.timedelta(days=364, hours=23) <= duration <= datetime.timedelta(days=365, hours=1)


def check_pyjwt_rsa(import_path, token_path, public_path):
    code = r'''
import base64
import sys
import jwt
assert getattr(jwt, "__version__", None) == "1.7.1"
token = open(sys.argv[1], "rb").read().strip()
parts = token.split(b".")
assert len(parts) == 3
pad = b"=" * ((4 - len(parts[2]) % 4) % 4)
sig = base64.urlsafe_b64decode(parts[2] + pad)
msg = parts[0] + b"." + parts[1]
pub = open(sys.argv[2], "rb").read()
alg = jwt.algorithms.get_default_algorithms()["RS256"]
key = alg.prepare_key(pub)
assert alg.verify(msg, key, sig) is True
bad = bytes([sig[0] ^ 1]) + sig[1:]
assert alg.verify(msg, key, bad) is False
'''
    env = os.environ.copy()
    if import_path is None:
        env.pop("PYTHONPATH", None)
    else:
        env["PYTHONPATH"] = import_path
    result = subprocess.run(
        ["python3", "-c", code, token_path, public_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        cwd="/tmp",
        timeout=20,
    )
    assert result.returncode == 0, result.stderr


def test_vendored_library_fixed_and_installed():
    private_key = serialization.load_pem_private_key(
        open("/home/user/new_key.pem", "rb").read(), password=None
    )
    token = make_jwt({"sub": "library-test", "role": "user"}, private_key)
    with tempfile.TemporaryDirectory(prefix="pyjwt-check-") as directory:
        token_path = os.path.join(directory, uuid.uuid4().hex)
        with open(token_path, "w") as f:
            f.write(token)
        check_pyjwt_rsa("/app/vendor/PyJWT-1.7.1", token_path, "/home/user/new_pub.pem")
        check_pyjwt_rsa(None, token_path, "/home/user/new_pub.pem")


def run_filter(path, expected):
    result = subprocess.run(
        ["python3", "/home/user/jwt_filter.py", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, "Filter exited nonzero: " + result.stderr
    assert result.stdout in (expected, expected + "\n"), repr(result.stdout)


def test_jwt_filter_with_generated_adversarial_inputs():
    new_private = serialization.load_pem_private_key(
        open("/home/user/new_key.pem", "rb").read(), password=None
    )
    old_private_path = "/tmp/old_key.pem"
    assert os.path.isfile(old_private_path), "Original compromised private key is unavailable"
    old_private = serialization.load_pem_private_key(
        open(old_private_path, "rb").read(), password=None
    )
    old_public = serialization.load_pem_public_key(open("/home/user/old_pub.pem", "rb").read())
    assert public_der(old_private) == public_der(old_public)

    unrelated_private = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    cases = [
        (make_jwt({"sub": "user1", "role": "admin"}, new_private), "ACCEPT"),
        (make_jwt({"sub": "ordinary-user", "role": "reader"}, new_private), "ACCEPT"),
        (make_jwt({"sub": "../etc/passwd", "role": "user"}, new_private), "REJECT"),
        (make_jwt({"sub": "user", "role": "..\\administrator"}, new_private), "REJECT"),
        (make_jwt({"sub": "%2e%2e%2fsecret", "role": "user"}, new_private), "REJECT"),
        (make_jwt({"sub": "user", "role": "%2E%2e%2Froot"}, new_private), "REJECT"),
        (make_jwt({"sub": "benign", "role": "user"}, old_private), "REJECT"),
        (make_jwt({"sub": "benign", "role": "user"}, unrelated_private), "REJECT"),
        (make_jwt({"sub": "benign"}, None, "none"), "REJECT"),
        (make_jwt({"sub": "benign"}, None, "NoNe"), "REJECT"),
        ("not-a-jwt", "REJECT"),
        ("abc.def", "REJECT"),
        ("@@@.@@@.@@@", "REJECT"),
    ]

    valid = make_jwt({"sub": "signed-user", "role": "user"}, new_private)
    parts = valid.split(".")
    replacement = "A" if parts[2][0] != "A" else "B"
    cases.append((parts[0] + "." + parts[1] + "." + replacement + parts[2][1:], "REJECT"))

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="jwt-filter-" + uuid.uuid4().hex + "-") as directory:
        materialized = []
        for token, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "w") as f:
                f.write(token)
            materialized.append((path, expected))
        assert len(materialized) > 0
        for path, expected in materialized:
            run_filter(path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
