#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

SRC_PATH = "/home/user/src/policy_checker.c"
BIN_PATH = "/home/user/policy_checker"
REPORT_PATH = "/home/user/final_report.log"

EXPECTED_REPORT_LINES = [
    "BUNDLE: /home/user/bundles/dev",
    "CERT: PASS",
    "INTEGRITY: PASS",
    "CSP: FAIL",
    "BUNDLE: /home/user/bundles/staging",
    "CERT: FAIL",
    "INTEGRITY: PASS",
    "CSP: PASS",
    "BUNDLE: /home/user/bundles/prod",
    "CERT: PASS",
    "INTEGRITY: FAIL",
    "CSP: PASS",
    "BUNDLE: /home/user/bundles/dr",
    "CERT: PASS",
    "INTEGRITY: PASS",
    "CSP: PASS"
]


def run_checker(bundle):
    result = subprocess.run(
        [BIN_PATH, str(bundle)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    return result.stdout.splitlines()


def expected_output(bundle, cert, integrity, csp):
    return [
        f"BUNDLE: {bundle}",
        f"CERT: {cert}",
        f"INTEGRITY: {integrity}",
        f"CSP: {csp}",
    ]


def openssl(*args):
    subprocess.run(
        ["openssl", *args],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )


@pytest.fixture(scope="session")
def generated_bundles():
    root = tempfile.mkdtemp(prefix="policy-check-")

    ca1_key = os.path.join(root, "ca1.key")
    ca1_pem = os.path.join(root, "ca1.pem")
    ca2_key = os.path.join(root, "ca2.key")
    ca2_pem = os.path.join(root, "ca2.pem")
    leaf1_key = os.path.join(root, "leaf1.key")
    leaf1_csr = os.path.join(root, "leaf1.csr")
    leaf1_pem = os.path.join(root, "leaf1.pem")
    leaf2_key = os.path.join(root, "leaf2.key")
    leaf2_csr = os.path.join(root, "leaf2.csr")
    leaf2_pem = os.path.join(root, "leaf2.pem")

    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
            "-keyout", ca1_key, "-out", ca1_pem,
            "-subj", "/CN=Verifier Random CA One")
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
            "-keyout", ca2_key, "-out", ca2_pem,
            "-subj", "/CN=Verifier Random CA Two")
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", leaf1_key,
            "-out", leaf1_csr, "-subj", "/CN=random-one.example")
    openssl("x509", "-req", "-in", leaf1_csr, "-CA", ca1_pem,
            "-CAkey", ca1_key, "-CAcreateserial", "-days", "2", "-out", leaf1_pem)
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", leaf2_key,
            "-out", leaf2_csr, "-subj", "/CN=random-two.example")
    openssl("x509", "-req", "-in", leaf2_csr, "-CA", ca2_pem,
            "-CAkey", ca2_key, "-CAcreateserial", "-days", "2", "-out", leaf2_pem)

    def make_bundle(name, ca, cert, csp, corrupt=False):
        bundle = os.path.join(root, name)
        assets = os.path.join(bundle, "assets")
        os.makedirs(assets)
        shutil.copyfile(ca, os.path.join(bundle, "ca.pem"))
        shutil.copyfile(cert, os.path.join(bundle, "cert.pem"))
        with open(os.path.join(bundle, "csp.txt"), "w", encoding="utf-8") as f:
            f.write(csp + "\n")

        files = {
            "assets/app.js": secrets.token_bytes(73),
            "assets/index.html": b"<h1>" + secrets.token_bytes(41) + b"</h1>\n",
        }
        for relative, data in files.items():
            with open(os.path.join(bundle, relative), "wb") as f:
                f.write(data)

        with open(os.path.join(bundle, "manifest.sha256"), "w", encoding="ascii") as f:
            for relative, data in files.items():
                f.write(f"{hashlib.sha256(data).hexdigest()}  {relative}\n")

        if corrupt:
            with open(os.path.join(bundle, "assets/app.js"), "ab") as f:
                f.write(secrets.token_bytes(17))
        return bundle

    bundles = {
        "valid": make_bundle(
            "valid", ca1_pem, leaf1_pem,
            "Content-Security-Policy: default-src 'unsafe-inline'; script-src 'self' https://cdn.example;"
        ),
        "bad_cert": make_bundle(
            "bad-cert", ca1_pem, leaf2_pem,
            "Content-Security-Policy: default-src 'self'; script-src 'self';"
        ),
        "bad_integrity": make_bundle(
            "bad-integrity", ca1_pem, leaf1_pem,
            "Content-Security-Policy: default-src 'self'; script-src 'self';",
            corrupt=True
        ),
        "bad_csp": make_bundle(
            "bad-csp", ca1_pem, leaf1_pem,
            "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline';"
        ),
    }
    yield bundles
    shutil.rmtree(root, ignore_errors=True)


def test_c_source_exists():
    assert os.path.isfile(SRC_PATH), f"Source file {SRC_PATH} is missing."


def test_binary_exists():
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} is missing."
    assert os.access(BIN_PATH, os.X_OK), f"Compiled binary {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled binary is not an ELF executable."


def test_final_report_content():
    assert os.path.isfile(REPORT_PATH), f"Final report {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]
    assert len(actual_lines) == len(EXPECTED_REPORT_LINES), (
        f"Expected {len(EXPECTED_REPORT_LINES)} lines in the report, but got {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, EXPECTED_REPORT_LINES)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}: expected '{expected}', got '{actual}'."
        )


def test_binary_reproduces_original_bundle_results():
    actual = []
    for name in ("dev", "staging", "prod", "dr"):
        actual.extend(run_checker(f"/home/user/bundles/{name}"))
    assert actual == EXPECTED_REPORT_LINES


def test_generated_valid_bundle(generated_bundles):
    bundle = generated_bundles["valid"]
    assert run_checker(bundle) == expected_output(bundle, "PASS", "PASS", "PASS")


def test_generated_certificate_failure(generated_bundles):
    bundle = generated_bundles["bad_cert"]
    assert run_checker(bundle) == expected_output(bundle, "FAIL", "PASS", "PASS")


def test_generated_integrity_failure(generated_bundles):
    bundle = generated_bundles["bad_integrity"]
    assert run_checker(bundle) == expected_output(bundle, "PASS", "FAIL", "PASS")


def test_generated_csp_failure(generated_bundles):
    bundle = generated_bundles["bad_csp"]
    assert run_checker(bundle) == expected_output(bundle, "PASS", "PASS", "FAIL")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
