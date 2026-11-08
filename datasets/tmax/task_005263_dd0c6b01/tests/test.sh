#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/audit_classifier.sh"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
TRUSTED_CA = "/app/trusted_ca.pem"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def run_classifier(file_path):
    try:
        result = subprocess.run(
            [SCRIPT_PATH, file_path],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


def test_adversarial_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, f"No files found in evil corpus directory: {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in clean corpus directory: {CLEAN_CORPUS_DIR}"

    bypassed_evil = []
    modified_clean = []

    for evil_file in evil_files:
        output = run_classifier(evil_file)
        if output != "EVIL\n":
            bypassed_evil.append((os.path.basename(evil_file), output.strip()))

    for clean_file in clean_files:
        output = run_classifier(clean_file)
        if output != "CLEAN\n":
            modified_clean.append((os.path.basename(clean_file), output.strip()))

    error_messages = []
    if bypassed_evil:
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed:")
        for f, out in bypassed_evil:
            error_messages.append(f"  - {f} (Output: {repr(out)})")

    if modified_clean:
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean modified/rejected:")
        for f, out in modified_clean:
            error_messages.append(f"  - {f} (Output: {repr(out)})")

    if error_messages:
        pytest.fail("\n".join(error_messages))


def extract_header(path, header):
    prefix = header.lower() + ":"
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.lower().startswith(prefix):
                return line.split(":", 1)[1].strip()
    raise AssertionError(f"Missing {header} in {path}")


def verify_cert_b64(cert_b64):
    cert_pem = base64.b64decode(cert_b64, validate=True)
    with tempfile.NamedTemporaryFile(mode="wb", suffix=".pem") as cert_file:
        cert_file.write(cert_pem)
        cert_file.flush()
        result = subprocess.run(
            ["openssl", "verify", "-CAfile", TRUSTED_CA, cert_file.name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0


def make_request(path, cert_b64, upload_path, session_token):
    encoded_path = base64.b64encode(upload_path.encode("utf-8")).decode("ascii")
    content = (
        "POST /upload HTTP/1.1\n"
        "Host: api.example.com\n"
        f"X-Upload-Path: {encoded_path}\n"
        f"X-Client-Cert: {cert_b64}\n"
        f"Cookie: session_token={session_token}; other=123\n"
        "\n"
        "data\n"
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def test_fresh_requests_are_classified_by_contents():
    clean_files = [
        os.path.join(CLEAN_CORPUS_DIR, f)
        for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    ]
    assert clean_files

    trusted_cert_b64 = extract_header(clean_files[0], "X-Client-Cert")
    assert verify_cert_b64(trusted_cert_b64), "Corpus trusted certificate does not verify against trusted_ca.pem"

    nonce = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix=f"audit-{nonce}-") as workdir:
        untrusted_key = os.path.join(workdir, f"key-{uuid.uuid4().hex}.pem")
        untrusted_cert = os.path.join(workdir, f"cert-{uuid.uuid4().hex}.pem")
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", untrusted_key, "-out", untrusted_cert, "-days", "1",
                "-subj", f"/CN={uuid.uuid4().hex}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        with open(untrusted_cert, "rb") as f:
            untrusted_cert_b64 = base64.b64encode(f.read()).decode("ascii")
        assert not verify_cert_b64(untrusted_cert_b64), "Fresh untrusted certificate unexpectedly verified"

        token = uuid.uuid4().hex
        cases = [
            (f"images/{uuid.uuid4().hex}/photo.png", trusted_cert_b64, f"AUTH_{token}", "CLEAN\n"),
            (f"images/{uuid.uuid4().hex}/../private/file.dat", trusted_cert_b64, f"AUTH_{token}", "EVIL\n"),
            (f"images/{uuid.uuid4().hex}/%2e%2e%2fprivate/file.dat", trusted_cert_b64, f"AUTH_{token}", "EVIL\n"),
            (f"images/{uuid.uuid4().hex}/photo.png", untrusted_cert_b64, f"AUTH_{token}", "EVIL\n"),
            (f"images/{uuid.uuid4().hex}/photo.png", trusted_cert_b64, f"GUEST_{token}", "EVIL\n"),
        ]
        random.SystemRandom().shuffle(cases)

        failures = []
        for upload_path, cert_b64, session_token, expected in cases:
            request_path = os.path.join(workdir, f"{uuid.uuid4().hex}.txt")
            make_request(request_path, cert_b64, upload_path, session_token)
            actual = run_classifier(request_path)
            if actual != expected:
                failures.append((expected.strip(), actual.strip()))

        assert not failures, f"Fresh content-derived classification failures: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
