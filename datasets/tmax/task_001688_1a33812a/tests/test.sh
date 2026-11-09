#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import glob
import hashlib
import json
import os
import secrets
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPT_PATH = "/home/user/auditor.py"
LOG_PATH = "/home/user/audit_trail.log"
CLEAN_DIR = "/app/corpora/clean/"
EVIL_DIR = "/app/corpora/evil/"


def run_auditor(target_dir):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    return subprocess.run(
        ["python3", SCRIPT_PATH, target_dir],
        capture_output=True,
        text=True,
        timeout=20,
    )


def parse_audit_log():
    if not os.path.exists(LOG_PATH):
        return {}

    results = {}
    with open(LOG_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(" ", 1)
            if len(parts) == 2:
                status, filepath = parts
                results[filepath] = status
    return results


def test_auditor_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Auditor script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.json"))
    assert len(clean_files) > 0, "No clean corpus files found to test."

    run_auditor(CLEAN_DIR)

    assert os.path.exists(LOG_PATH), f"Audit log not created at {LOG_PATH} after processing clean corpus."
    log_results = parse_audit_log()

    rejected_clean = []
    missing_clean = []
    for cf in clean_files:
        if cf not in log_results:
            missing_clean.append(cf)
        elif log_results[cf] != "[ACCEPT]":
            rejected_clean.append(cf)

    error_msgs = []
    if missing_clean:
        error_msgs.append(f"{len(missing_clean)} clean files were not logged. Examples: {missing_clean[:3]}")
    if rejected_clean:
        error_msgs.append(f"{len(rejected_clean)} of {len(clean_files)} clean files were incorrectly REJECTED. Examples: {rejected_clean[:3]}")
    assert not error_msgs, " | ".join(error_msgs)


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.json"))
    assert len(evil_files) > 0, "No evil corpus files found to test."

    run_auditor(EVIL_DIR)

    assert os.path.exists(LOG_PATH), f"Audit log not created at {LOG_PATH} after processing evil corpus."
    log_results = parse_audit_log()

    accepted_evil = []
    missing_evil = []
    for ef in evil_files:
        if ef not in log_results:
            missing_evil.append(ef)
        elif log_results[ef] != "[REJECT]":
            accepted_evil.append(ef)

    error_msgs = []
    if missing_evil:
        error_msgs.append(f"{len(missing_evil)} evil files were not logged. Examples: {missing_evil[:3]}")
    if accepted_evil:
        error_msgs.append(f"{len(accepted_evil)} of {len(evil_files)} evil files bypassed the filter and were ACCEPTED. Examples: {accepted_evil[:3]}")
    assert not error_msgs, " | ".join(error_msgs)


def make_root(common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.datetime(2020, 1, 1))
        .not_valid_after(datetime.datetime(2035, 1, 1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    return key, cert


def make_leaf(root_key, root_cert, common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(root_cert.subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.datetime(2020, 1, 1))
        .not_valid_after(datetime.datetime(2035, 1, 1))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(root_key, hashes.SHA256())
    )
    return cert


def encode_cert(cert):
    pem = cert.public_bytes(serialization.Encoding.PEM)
    return base64.b64encode(pem).decode("ascii")


def valid_token(data):
    return data + "." + hashlib.sha256(data.encode("utf-8")).hexdigest()


def test_randomized_mixed_corpus_exercises_validation_logic():
    nonce = secrets.token_hex(8)
    root_key, root_cert = make_root("root-" + nonce)
    leaf_cert = make_leaf(root_key, root_cert, "leaf-" + nonce)
    _, unrelated_root = make_root("other-" + nonce)

    valid_chain = [encode_cert(leaf_cert), encode_cert(root_cert)]
    wrong_chain = [encode_cert(leaf_cert), encode_cert(unrelated_root)]
    token_data = "payload-" + secrets.token_hex(16)
    good_token = valid_token(token_data)
    bad_token = token_data + "." + ("0" * 64)

    def payload(cookie, token=good_token, chain=None):
        return {
            "headers": {"Cookie": cookie},
            "cert_chain": valid_chain if chain is None else chain,
            "compliance_token": token,
        }

    cases = [
        (payload("session=user_" + secrets.token_hex(5)), "ACCEPT"),
        (payload("session=admin_safevalue"), "ACCEPT"),
        (payload("preference=a|b; session=user_ok"), "ACCEPT"),
        (payload("session=admin_value;other=x"), "REJECT"),
        (payload("session=admin_$(id)"), "REJECT"),
        (payload("session=admin_x|cat"), "REJECT"),
        (payload("session=user_ok", token=bad_token), "REJECT"),
        (payload("session=user_ok", chain=wrong_chain), "REJECT"),
        (payload("session=user_ok", chain=["not@@base64!!", encode_cert(root_cert)]), "REJECT"),
    ]

    target_dir = tempfile.mkdtemp(prefix="requests_" + secrets.token_hex(6) + "_")
    expected = []
    for body, status in cases:
        filename = secrets.token_hex(10) + ".json"
        path = os.path.join(target_dir, filename)
        with open(path, "w") as f:
            json.dump(body, f)
        expected.append((path, status))

    result = run_auditor(target_dir)
    assert result.returncode == 0, f"Auditor exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(LOG_PATH), "Auditor did not create the audit log"

    with open(LOG_PATH, "r") as f:
        actual_lines = f.read().splitlines()

    expected_lines = [f"[{status}] {path}" for path, status in sorted(expected)]
    assert actual_lines == expected_lines, (
        "Audit log must contain exactly one correctly classified line per JSON file, "
        "sorted alphabetically.\nExpected: " + repr(expected_lines) + "\nActual: " + repr(actual_lines)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
