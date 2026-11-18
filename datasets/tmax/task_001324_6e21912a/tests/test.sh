#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPT_PATH = "/home/user/detector.py"
BINARY_PATH = "/app/c2_auth_check"


def run_detector(input_dir, output_file):
    assert os.path.exists(SCRIPT_PATH), f"Detector script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Detector path is not a file: {SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, input_dir, output_file],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Detector script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.exists(output_file), f"Output file {output_file} was not created."


def load_results(output_file):
    try:
        with open(output_file, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {output_file} is not valid JSON.")
    assert isinstance(results, dict), "Output JSON must be a dictionary."
    return results


@contextlib.contextmanager
def binary_unavailable():
    data = None
    mode = None
    if os.path.exists(BINARY_PATH):
        with open(BINARY_PATH, "rb") as f:
            data = f.read()
        mode = os.stat(BINARY_PATH).st_mode & 0o7777
        os.remove(BINARY_PATH)
    try:
        yield
    finally:
        if data is not None:
            with open(BINARY_PATH, "wb") as f:
                f.write(data)
            os.chmod(BINARY_PATH, mode)


def test_evil_corpus_classification():
    evil_dir = "/test/corpus/evil/"
    out_file = "/tmp/out_evil.json"
    if os.path.exists(out_file):
        os.remove(out_file)

    run_detector(evil_dir, out_file)
    results = load_results(out_file)
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    bypassed = []
    for f in evil_files:
        if f not in results:
            bypassed.append(f"{f} (missing from output)")
        elif results[f] != "C2":
            bypassed.append(f"{f} (classified as {results[f]})")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join(bypassed[:10]) + ("..." if len(bypassed) > 10 else ""))


def test_clean_corpus_classification():
    clean_dir = "/test/corpus/clean/"
    out_file = "/tmp/out_clean.json"
    if os.path.exists(out_file):
        os.remove(out_file)

    run_detector(clean_dir, out_file)
    results = load_results(out_file)
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    modified = []
    for f in clean_files:
        if f not in results:
            modified.append(f"{f} (missing from output)")
        elif results[f] != "BENIGN":
            modified.append(f"{f} (classified as {results[f]})")

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified: " + ", ".join(modified[:10]) + ("..." if len(modified) > 10 else ""))


def test_no_binary_invocation():
    clean_dir = "/test/corpus/clean/"
    out_file = "/tmp/out_clean_isolated.json"
    if os.path.exists(out_file):
        os.remove(out_file)

    with binary_unavailable():
        run_detector(clean_dir, out_file)

    results = load_results(out_file)
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(results) == len(clean_files), "Detector failed to process all files when binary was removed."


def make_certificate(key, common_name, issuer_common_name, require_zero_hash, serial_start):
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer_common_name)])
    not_before = datetime.datetime(2020, 1, 1)
    not_after = datetime.datetime(2035, 1, 1)

    for serial in range(serial_start, serial_start + 30000):
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(serial)
            .not_valid_before(not_before)
            .not_valid_after(not_after)
            .sign(key, hashes.SHA256())
        )
        der = cert.public_bytes(serialization.Encoding.DER)
        is_zero = hashlib.sha256(der).digest()[0] == 0
        if is_zero == require_zero_hash:
            return cert, serial + 1

    raise AssertionError("Could not generate a certificate with the requested hash prefix")


def derive_expected(cert):
    common_names = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    has_suffix = bool(common_names) and common_names[0].value.endswith(".c2.internal")
    same_name = cert.subject == cert.issuer
    der = cert.public_bytes(serialization.Encoding.DER)
    hash_matches = hashlib.sha256(der).digest()[0] == 0
    return "C2" if same_name and has_suffix and hash_matches else "BENIGN"


def test_fresh_certificates_with_derived_answers_and_no_binary():
    input_dir = tempfile.mkdtemp(prefix="captured_certs_")
    output_file = os.path.join(tempfile.mkdtemp(prefix="detector_output_"), "results.json")
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    # Exercise every required predicate independently. Names and paths do not reveal labels.
    cases = [
        ("node.c2.internal", "node.c2.internal", True),
        (".c2.internal", ".c2.internal", True),
        ("node.c2.internal", "node.c2.internal", False),
        ("node.example", "node.example", True),
        ("node.C2.internal", "node.C2.internal", True),
        ("node.c2.internal", "different.c2.internal", True),
        ("node.c2.internal.invalid", "node.c2.internal.invalid", True),
    ]

    expected = {}
    serial = 1
    try:
        for common_name, issuer_common_name, require_zero_hash in cases:
            cert, serial = make_certificate(
                key, common_name, issuer_common_name, require_zero_hash, serial
            )
            filename = uuid.uuid4().hex + ".pem"
            with open(os.path.join(input_dir, filename), "wb") as f:
                f.write(cert.public_bytes(serialization.Encoding.PEM))
            expected[filename] = derive_expected(cert)

        assert "C2" in expected.values() and "BENIGN" in expected.values()

        with binary_unavailable():
            run_detector(input_dir, output_file)

        actual = load_results(output_file)
        assert actual == expected, (
            "Detector did not implement the X.509 name, common-name suffix, and DER SHA-256 criteria "
            f"on fresh certificates. Expected {expected}, got {actual}."
        )
    finally:
        shutil.rmtree(input_dir, ignore_errors=True)
        shutil.rmtree(os.path.dirname(output_file), ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
