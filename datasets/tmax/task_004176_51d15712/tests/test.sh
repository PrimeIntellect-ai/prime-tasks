#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import filecmp
import hashlib
import hmac
import importlib.metadata
import json
import os
import pathlib
import random
import secrets
import subprocess
import tempfile
import uuid
from urllib.parse import unquote, urlparse

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def test_pyjwt_typo_fixed():
    """Verify that the typo in the vendored pyjwt-custom library has been fixed."""
    path = "/app/vendored/pyjwt-custom/jwt/api_jwt.py"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "def verify_signature(" in content, "The typo was not fixed: 'def verify_signature(' not found."
    assert "def verfy_signature(" not in content, "The typo 'def verfy_signature(' is still present in the file."


def test_vendored_pyjwt_is_installed_editable():
    """Verify that the repaired vendored package was actually installed with pip -e."""
    expected = os.path.realpath("/app/vendored/pyjwt-custom")
    dist = importlib.metadata.distribution("PyJWT")
    direct_url_text = dist.read_text("direct_url.json")
    assert direct_url_text, "PyJWT has no editable-install direct_url.json metadata"
    direct_url = json.loads(direct_url_text)
    assert direct_url.get("dir_info", {}).get("editable") is True, "PyJWT is not installed editable"
    installed_from = os.path.realpath(unquote(urlparse(direct_url["url"]).path))
    assert installed_from == expected, f"PyJWT was installed from {installed_from}, not {expected}"

    proc = subprocess.run(
        ["python3", "-c", "import os,jwt; print(os.path.realpath(jwt.__file__))"],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    imported_path = proc.stdout.strip()
    assert os.path.commonpath([expected, imported_path]) == expected, (
        f"Imported jwt module is not from the vendored package: {imported_path}"
    )


def test_payload_filter_adversarial_corpus():
    """
    Preserve the original fixed-corpus assertions for all supplied clean and evil files.
    """
    script_path = "/home/user/payload_filter.py"
    assert os.path.isfile(script_path), f"Payload filter script not found at {script_path}"

    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus), f"Clean corpus missing at {clean_corpus}"
    assert os.path.isdir(evil_corpus), f"Evil corpus missing at {evil_corpus}"

    clean_files = set(os.listdir(clean_corpus))
    evil_files = set(os.listdir(evil_corpus))

    with tempfile.TemporaryDirectory() as tmp_clean_out, tempfile.TemporaryDirectory() as tmp_evil_out:
        subprocess.run(
            ["python3", script_path, "--input-dir", clean_corpus, "--output-dir", tmp_clean_out],
            capture_output=True, text=True
        )
        subprocess.run(
            ["python3", script_path, "--input-dir", evil_corpus, "--output-dir", tmp_evil_out],
            capture_output=True, text=True
        )

        clean_out_files = set(os.listdir(tmp_clean_out))
        evil_out_files = set(os.listdir(tmp_evil_out))

        clean_missing = clean_files - clean_out_files
        clean_modified = []
        for f in clean_files.intersection(clean_out_files):
            src = os.path.join(clean_corpus, f)
            dst = os.path.join(tmp_clean_out, f)
            if not filecmp.cmp(src, dst, shallow=False):
                clean_modified.append(f)

        clean_failed = len(clean_missing) + len(clean_modified)
        evil_bypassed = evil_out_files.intersection(evil_files)

        errors = []
        if clean_failed > 0:
            errors.append(f"{clean_failed} of {len(clean_files)} clean modified or missing. "
                          f"Missing: {list(clean_missing)}, Modified: {clean_modified}")
        if len(evil_bypassed) > 0:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. "
                          f"Bypassed basenames: {list(evil_bypassed)}")
        if errors:
            pytest.fail(" | ".join(errors))


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def _make_jwt(payload, secret):
    header = {"alg": "HS256", "typ": "JWT"}
    first = _b64url(json.dumps(header, separators=(",", ":"), sort_keys=True).encode())
    second = _b64url(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    signing_input = first + b"." + second
    signature = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    return (signing_input + b"." + _b64url(signature)).decode()


def _make_cert(signing_key, issuer_name, common_name, not_before, not_after):
    leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    return (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer_name)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .sign(signing_key, hashes.SHA256())
        .public_bytes(serialization.Encoding.PEM)
    )


def test_payload_filter_randomized_mixed_inputs():
    """Exercise certificate signatures, wordlist cracking, and roles in one unlabeled directory."""
    script_path = "/home/user/payload_filter.py"
    assert os.path.isfile(script_path), f"Payload filter script not found at {script_path}"

    with open("/app/rogue_ca.key", "rb") as f:
        ca_key = serialization.load_pem_private_key(f.read(), password=None)
    with open("/app/rogue_ca.pem", "rb") as f:
        ca_cert = x509.load_pem_x509_certificate(f.read())
    with open("/app/wordlist.txt", "r") as f:
        words = [line.strip() for line in f if line.strip()]
    assert words

    rng = secrets.SystemRandom()
    selected = rng.sample(words, min(4, len(words)))
    while len(selected) < 4:
        selected.append(rng.choice(words))

    now = datetime.datetime.now(datetime.timezone.utc)
    valid_before = now - datetime.timedelta(hours=1)
    valid_after = now + datetime.timedelta(days=2)

    evil_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    unknown_secret = "not-in-wordlist-" + secrets.token_hex(24)
    while unknown_secret in words:
        unknown_secret = "not-in-wordlist-" + secrets.token_hex(24)

    cases = []

    # Multiple accepted records use verifier-selected secrets from the actual wordlist.
    for secret in selected[:3]:
        cert = _make_cert(ca_key, ca_cert.subject, "ok-" + uuid.uuid4().hex,
                          valid_before, valid_after)
        token = _make_jwt({"role": "operator", "nonce": secrets.token_hex(8)}, secret)
        cases.append((True, cert, token))

    # Issuer name is forged to match the rogue CA, but the signature uses another key.
    forged = _make_cert(evil_key, ca_cert.subject, "forged-" + uuid.uuid4().hex,
                        valid_before, valid_after)
    cases.append((False, forged, _make_jwt({"role": "operator"}, selected[0])))

    # Proper CA certificate but a secret absent from the wordlist.
    valid_cert = _make_cert(ca_key, ca_cert.subject, "unknown-secret-" + uuid.uuid4().hex,
                            valid_before, valid_after)
    cases.append((False, valid_cert, _make_jwt({"role": "operator"}, unknown_secret)))

    # Proper CA certificate and crackable token, but the required role is absent or wrong.
    for payload in ({"role": "admin"}, {"scope": "operator"}, {"role": "Operator"}):
        cert = _make_cert(ca_key, ca_cert.subject, "wrong-role-" + uuid.uuid4().hex,
                          valid_before, valid_after)
        cases.append((False, cert, _make_jwt(payload, selected[3])))

    # A CA-signed but expired certificate is not valid.
    expired = _make_cert(ca_key, ca_cert.subject, "expired-" + uuid.uuid4().hex,
                         now - datetime.timedelta(days=3), now - datetime.timedelta(days=1))
    cases.append((False, expired, _make_jwt({"role": "operator"}, selected[1])))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="pf-" + uuid.uuid4().hex + "-") as root:
        input_dir = os.path.join(root, uuid.uuid4().hex)
        output_dir = os.path.join(root, uuid.uuid4().hex)
        os.mkdir(input_dir)
        os.mkdir(output_dir)

        expected = set()
        original_bytes = {}
        for accepted, cert, token in cases:
            name = uuid.uuid4().hex + ".json"
            body = json.dumps({
                "tls_cert": base64.b64encode(cert).decode(),
                "auth_token": token,
            }, indent=rng.choice([None, 1, 2])).encode()
            path = os.path.join(input_dir, name)
            with open(path, "wb") as f:
                f.write(body)
            original_bytes[name] = body
            if accepted:
                expected.add(name)

        proc = subprocess.run(
            ["python3", script_path, "--input-dir", input_dir, "--output-dir", output_dir],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"Classifier failed: stdout={proc.stdout!r} stderr={proc.stderr!r}"

        actual = set(os.listdir(output_dir))
        assert actual == expected, f"Expected accepted files {sorted(expected)}, got {sorted(actual)}"
        for name in expected:
            output_path = os.path.join(output_dir, name)
            assert pathlib.Path(output_path).is_file(), f"Output is not a regular file: {name}"
            with open(output_path, "rb") as f:
                assert f.read() == original_bytes[name], f"Accepted file was modified: {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
