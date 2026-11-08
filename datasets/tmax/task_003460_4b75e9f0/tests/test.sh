#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPT_PATH = "/home/user/cert_filter.py"
EVIL_CORPUS = "/app/corpus/evil/"
CLEAN_CORPUS = "/app/corpus/clean/"


def run_script(corpus_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, corpus_path],
        capture_output=True,
        text=True
    )
    return result.stdout, result.stderr, result.returncode


def parse_output(stdout):
    results = {}
    for line in stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        if " - " in line:
            filename, status = line.rsplit(" - ", 1)
            results[filename.strip()] = status.strip()
    return results


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Student script not found at {SCRIPT_PATH}"


def test_evil_corpus():
    stdout, stderr, returncode = run_script(EVIL_CORPUS)
    assert returncode == 0, f"Script failed on evil corpus with return code {returncode}.\nStderr: {stderr}"

    results = parse_output(stdout)
    evil_files = [f.name for f in Path(EVIL_CORPUS).glob("*.pem")]

    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed = []
    for f in evil_files:
        if f not in results:
            bypassed.append(f"{f} (missing from output)")
        elif results[f] != "EVIL":
            bypassed.append(f"{f} (marked as {results[f]})")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed:\n" + "\n".join(bypassed))


def test_clean_corpus():
    stdout, stderr, returncode = run_script(CLEAN_CORPUS)
    assert returncode == 0, f"Script failed on clean corpus with return code {returncode}.\nStderr: {stderr}"

    results = parse_output(stdout)
    clean_files = [f.name for f in Path(CLEAN_CORPUS).glob("*.pem")]

    assert len(clean_files) > 0, "No files found in clean corpus."

    modified = []
    for f in clean_files:
        if f not in results:
            modified.append(f"{f} (missing from output)")
        elif results[f] != "CLEAN":
            modified.append(f"{f} (marked as {results[f]})")

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified (flagged as EVIL):\n" + "\n".join(modified))


def make_name(org=None, common_name="Generated Certificate"):
    attrs = []
    if org is not None:
        attrs.append(x509.NameAttribute(NameOID.ORGANIZATION_NAME, org))
    attrs.append(x509.NameAttribute(NameOID.COMMON_NAME, common_name))
    return x509.Name(attrs)


def write_sha256_cert(path, issuer_org, subject_org="ExampleSubject", mode=0o644):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.utcnow()
    cert = (
        x509.CertificateBuilder()
        .subject_name(make_name(subject_org))
        .issuer_name(make_name(issuer_org, "Generated Issuer"))
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=5))
        .sign(key, hashes.SHA256())
    )
    Path(path).write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    os.chmod(path, mode)


def write_md5_cert(path, org="AcmeCorp", mode=0o644):
    config = Path(path).parent / ("openssl_" + secrets.token_hex(6) + ".cnf")
    key_path = Path(path).parent / ("key_" + secrets.token_hex(6) + ".pem")
    config.write_text("""openssl_conf = openssl_init
[openssl_init]
providers = provider_sect
[provider_sect]
default = default_sect
legacy = legacy_sect
[default_sect]
activate = 1
[legacy_sect]
activate = 1
""")
    env = os.environ.copy()
    env["OPENSSL_CONF"] = str(config)
    try:
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048",
             "-keyout", str(key_path), "-out", str(path), "-days", "5",
             "-nodes", "-subj", f"/O={org}/CN=Generated", "-md5"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
    finally:
        config.unlink(missing_ok=True)
        key_path.unlink(missing_ok=True)
    os.chmod(path, mode)


def assert_exact_output(stdout, expected):
    lines = stdout.splitlines()
    assert len(lines) == len(expected), (
        f"Expected exactly {len(expected)} output lines, got {len(lines)}:\n{stdout}"
    )
    pattern = re.compile(r"^[^/\\]+\.pem - (?:CLEAN|EVIL)$")
    for line in lines:
        assert pattern.fullmatch(line), f"Invalid output line format: {line!r}"
    expected_lines = {f"{name} - {status}" for name, status in expected.items()}
    assert set(lines) == expected_lines, (
        f"Output did not exactly match expected classifications.\n"
        f"Expected: {sorted(expected_lines)}\nGot: {sorted(lines)}"
    )


def test_randomized_mixed_corpus_and_exact_output():
    corpus = Path(tempfile.mkdtemp(prefix="cert-check-" + secrets.token_hex(8) + "-"))
    try:
        cases = [
            ("clean_subject_match", "CLEAN"),
            ("clean_near_issuer", "CLEAN"),
            ("evil_issuer", "EVIL"),
            ("evil_permissions", "EVIL"),
            ("evil_md5", "EVIL"),
            ("evil_all_conditions", "EVIL"),
        ]
        random.SystemRandom().shuffle(cases)
        expected = {}

        for kind, status in cases:
            filename = f"document_{secrets.token_hex(10)}.pem"
            path = corpus / filename
            if kind == "clean_subject_match":
                write_sha256_cert(path, "AcmeCorp", subject_org="PwnedLtd", mode=0o644)
            elif kind == "clean_near_issuer":
                write_sha256_cert(path, "PwnedLtd ", subject_org="AcmeCorp", mode=0o644)
            elif kind == "evil_issuer":
                write_sha256_cert(path, "PwnedLtd", subject_org="AcmeCorp", mode=0o644)
            elif kind == "evil_permissions":
                write_sha256_cert(path, "AcmeCorp", subject_org="AcmeCorp", mode=0o646)
            elif kind == "evil_md5":
                write_md5_cert(path, "AcmeCorp", mode=0o644)
            elif kind == "evil_all_conditions":
                write_md5_cert(path, "PwnedLtd", mode=0o666)
            expected[filename] = status

        (corpus / ("ignored_" + secrets.token_hex(5) + ".txt")).write_text("not a certificate")

        stdout, stderr, returncode = run_script(str(corpus))
        assert returncode == 0, f"Script failed on randomized corpus with return code {returncode}.\nStderr: {stderr}"
        assert_exact_output(stdout, expected)
    finally:
        shutil.rmtree(corpus, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
