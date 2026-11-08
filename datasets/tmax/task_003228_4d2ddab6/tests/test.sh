#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import json
import random
import secrets
import subprocess
import tempfile
import datetime
import pytest

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def test_blocked_ips():
    """Verify that the correct IPs were extracted from the video."""
    blocked_ips_path = "/home/user/blocked_ips.txt"
    assert os.path.exists(blocked_ips_path), f"File not found: {blocked_ips_path}"

    with open(blocked_ips_path, "r") as f:
        ips = {line.strip() for line in f if line.strip()}

    expected_ips = {"192.168.1.105", "10.0.0.52"}
    assert ips == expected_ips, f"Expected IPs {expected_ips}, but found {ips}"


def test_upload_filter_clean_corpus():
    """Verify that the upload filter accepts all clean files."""
    script_path = "/home/user/upload_filter.py"
    assert os.path.exists(script_path), f"Script not found: {script_path}"

    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert clean_files, f"No clean files found in {clean_dir}"

    failed_clean = []
    for f in clean_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean files rejected: {failed_clean}"


def test_upload_filter_evil_corpus():
    """Verify that the upload filter rejects all evil files."""
    script_path = "/home/user/upload_filter.py"
    assert os.path.exists(script_path), f"Script not found: {script_path}"

    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert evil_files, f"No evil files found in {evil_dir}"

    bypassed_evil = []
    for f in evil_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode == 0:
            bypassed_evil.append(os.path.basename(f))

    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed: {bypassed_evil}"


def _new_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _make_cert(common_name, subject_key, issuer_cert=None, issuer_key=None, is_ca=False):
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    issuer = issuer_cert.subject if issuer_cert is not None else subject
    signing_key = issuer_key if issuer_key is not None else subject_key
    now = datetime.datetime.utcnow()
    return (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(subject_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=is_ca, path_length=None), critical=True)
        .sign(signing_key, hashes.SHA256())
    )


def _pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM).decode("ascii")


def test_upload_filter_generated_cases():
    """Exercise path, extension, and certificate checks at unpredictable paths."""
    script_path = "/home/user/upload_filter.py"
    root_path = "/app/root_ca.pem"
    assert os.path.isfile(script_path), f"Regular script file not found: {script_path}"

    with open(root_path, "rb") as f:
        original_root = f.read()

    token = secrets.token_hex(10)
    root_key = _new_key()
    root_cert = _make_cert("Generated Root " + token, root_key, is_ca=True)
    intermediate_key = _new_key()
    intermediate_cert = _make_cert(
        "Generated Intermediate " + token,
        intermediate_key,
        root_cert,
        root_key,
        is_ca=True,
    )
    client_key = _new_key()
    client_cert = _make_cert(
        "Generated Client " + token,
        client_key,
        intermediate_cert,
        intermediate_key,
    )

    # A parsable client certificate whose claimed issuer did not sign it.
    wrong_signer_key = _new_key()
    wrong_client_key = _new_key()
    wrong_client_cert = _make_cert(
        "Generated Client " + token,
        wrong_client_key,
        intermediate_cert,
        wrong_signer_key,
    )

    # A complete internally consistent chain that is not rooted at /app/root_ca.pem.
    rogue_root_key = _new_key()
    rogue_root_cert = _make_cert("Rogue Root " + token, rogue_root_key, is_ca=True)
    rogue_intermediate_key = _new_key()
    rogue_intermediate_cert = _make_cert(
        "Rogue Intermediate " + token,
        rogue_intermediate_key,
        rogue_root_cert,
        rogue_root_key,
        is_ca=True,
    )
    rogue_client_key = _new_key()
    rogue_client_cert = _make_cert(
        "Rogue Client " + token,
        rogue_client_key,
        rogue_intermediate_cert,
        rogue_intermediate_key,
    )

    valid_client = _pem(client_cert)
    valid_intermediate = _pem(intermediate_cert)
    safe_path = f"uploads/{token}/asset.jpg"

    def request(path, client=valid_client, intermediate=valid_intermediate):
        return {
            "target_path": path,
            "client_cert_pem": client,
            "intermediate_cert_pem": intermediate,
        }

    cases = [
        (request(safe_path), 0),
        (request(f"uploads/{token}/picture.png"), 0),
        (request(f"../uploads/{token}/asset.jpg"), 1),
        (request(f"uploads/{token}/..\\..\\secret.jpg"), 1),
        (request("/etc/shadow"), 1),
        (request(f"uploads/{token}/../../outside.jpg"), 1),
        (request(f"uploads_{token}/asset.jpg"), 1),
        (request(f"uploads/{token}/payload.sh"), 1),
        (request(f"uploads/{token}/payload.py"), 1),
        (request(f"uploads/{token}/payload.exe"), 1),
        (request(f"uploads/{token}/payload.php"), 1),
        (request(safe_path, _pem(wrong_client_cert), valid_intermediate), 1),
        (request(safe_path, _pem(rogue_client_cert), _pem(rogue_intermediate_cert)), 1),
    ]
    random.SystemRandom().shuffle(cases)
    generated_root = root_cert.public_bytes(serialization.Encoding.PEM)

    try:
        with tempfile.TemporaryDirectory(prefix="uf_" + token + "_") as temp_dir:
            for payload, expected_code in cases:
                case_path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
                with open(case_path, "w", encoding="utf-8") as f:
                    json.dump(payload, f)

                # Restore the generated trust anchor before every independent run.
                with open(root_path, "wb") as f:
                    f.write(generated_root)

                result = subprocess.run(
                    ["python3", script_path, case_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                )
                assert result.returncode == expected_code, (
                    f"Wrong classification for generated request with target "
                    f"{payload['target_path']!r}: expected {expected_code}, "
                    f"got {result.returncode}"
                )
                assert result.stdout == b"", "upload_filter.py wrote to stdout"
                assert result.stderr == b"", "upload_filter.py wrote to stderr"
    finally:
        with open(root_path, "wb") as f:
            f.write(original_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
