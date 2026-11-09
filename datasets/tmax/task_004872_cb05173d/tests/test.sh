#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

import pytest


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


@pytest.fixture(scope="session")
def checker_environment():
    work = tempfile.mkdtemp(prefix="checker-verifier-")
    binary = os.path.join(work, "fixed_checker")
    build = run(["go", "build", "-o", binary, "/home/user/fixed_checker.go"])
    assert build.returncode == 0, f"fixed_checker.go failed to compile:\n{build.stderr}"

    def make_root(prefix, common_name):
        key = os.path.join(work, prefix + ".key")
        cert = os.path.join(work, prefix + ".pem")
        result = run([
            "openssl", "req", "-x509", "-sha256", "-days", "30", "-nodes",
            "-newkey", "rsa:2048", "-subj", f"/CN={common_name}",
            "-addext", "basicConstraints=critical,CA:TRUE",
            "-keyout", key, "-out", cert,
        ])
        assert result.returncode == 0, result.stderr
        return key, cert

    def make_leaf(prefix, root_key, root_cert, dns_name, serial):
        key = os.path.join(work, prefix + ".key")
        csr = os.path.join(work, prefix + ".csr")
        cert = os.path.join(work, prefix + ".pem")
        ext = os.path.join(work, prefix + ".cnf")

        result = run([
            "openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key, "-out", csr, "-subj", f"/CN={dns_name}",
        ])
        assert result.returncode == 0, result.stderr

        with open(ext, "w") as f:
            f.write(f"subjectAltName=DNS:{dns_name}\n")

        result = run([
            "openssl", "x509", "-req", "-in", csr, "-CA", root_cert,
            "-CAkey", root_key, "-set_serial", str(serial), "-out", cert,
            "-days", "30", "-sha256", "-extfile", ext,
        ])
        assert result.returncode == 0, result.stderr
        return cert

    trusted_key, trusted_cert = make_root("trusted", "VerifierTrustedRoot")
    rogue_key, rogue_cert = make_root("rogue", "VerifierRogueRoot")
    valid_leaf = make_leaf(
        "valid-leaf", trusted_key, trusted_cert, "secure.internal.com", 1001
    )
    wrong_dns_leaf = make_leaf(
        "wrong-dns-leaf", trusted_key, trusted_cert, "wrong.internal.com", 1002
    )
    rogue_leaf = make_leaf(
        "rogue-leaf", rogue_key, rogue_cert, "secure.internal.com", 1003
    )

    env = {
        "work": work,
        "binary": binary,
        "trusted_cert": trusted_cert,
        "rogue_cert": rogue_cert,
        "valid_leaf": valid_leaf,
        "wrong_dns_leaf": wrong_dns_leaf,
        "rogue_leaf": rogue_leaf,
    }
    yield env
    shutil.rmtree(work, ignore_errors=True)


def test_cwe_file():
    cwe_path = "/home/user/cwe.txt"
    assert os.path.isfile(cwe_path), f"File {cwe_path} is missing."
    with open(cwe_path, "r") as f:
        content = f.read().strip()
    assert "CWE-295" in content, f"Expected 'CWE-295' in {cwe_path}, but got '{content}'."


def test_redacted_output():
    output_path = "/home/user/redacted_output.log"
    assert os.path.isfile(output_path), f"File {output_path} is missing."

    expected_output = """[INFO] Transaction 101 started. User: alice.
[DEBUG] Processing payment method: XXXX-XXXX-XXXX-XXXX
[INFO] Transaction 101 successful.
[DEBUG] User bob backup payment: XXXX-XXXX-XXXX-XXXX (Visa)
[INFO] End of log."""

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == expected_output, "The content of redacted_output.log does not match the expected redacted log."


def test_fixed_checker_content():
    go_path = "/home/user/fixed_checker.go"
    assert os.path.isfile(go_path), f"File {go_path} is missing."

    with open(go_path, "r") as f:
        content = f.read()

    assert "x509.NewCertPool(" in content or "x509.NewCertPool ()" in content, "fixed_checker.go does not use x509.NewCertPool()."
    assert "x509.VerifyOptions" in content, "fixed_checker.go does not use x509.VerifyOptions."

    has_regex_1 = re.search(r'\[0-9\]\{4\}-\[0-9\]\{4\}-\[0-9\]\{4\}-\[0-9\]\{4\}', content)
    has_regex_2 = re.search(r'\\d\{4\}-\\d\{4\}-\\d\{4\}-\\d\{4\}', content)
    assert has_regex_1 or has_regex_2, "fixed_checker.go does not contain the expected regex for credit card redaction."


def test_fixed_checker_compiles():
    go_path = "/home/user/fixed_checker.go"
    assert os.path.isfile(go_path), f"File {go_path} is missing."

    result = run(["go", "build", "-o", "/dev/null", go_path])
    assert result.returncode == 0, f"fixed_checker.go failed to compile:\n{result.stderr}"


def test_saved_output_was_produced_by_checker(checker_environment):
    result = run([
        checker_environment["binary"],
        "/home/user/certs/leaf.pem",
        "/home/user/certs/root.pem",
        "/home/user/logs/transactions.log",
    ])
    assert result.returncode == 0, result.stderr
    with open("/home/user/redacted_output.log", "r") as f:
        saved = f.read()
    assert result.stdout.strip() == saved.strip()


def test_valid_certificate_and_dynamic_redaction(checker_environment):
    log_path = os.path.join(checker_environment["work"], "dynamic.log")
    log_content = (
        "first=4821-0374-6650-9123\n"
        "two cards: 0000-1111-2222-3333 and 9876-5432-1098-7654\n"
        "leave these unchanged: 1234-5678-9012 and abcd-5678-9012-3456\n"
    )
    with open(log_path, "w") as f:
        f.write(log_content)

    expected = re.sub(
        r"[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}",
        "XXXX-XXXX-XXXX-XXXX",
        log_content,
    )
    result = run([
        checker_environment["binary"],
        checker_environment["valid_leaf"],
        checker_environment["trusted_cert"],
        log_path,
    ])
    assert result.returncode == 0, result.stderr
    assert result.stdout == expected


def test_rejects_leaf_from_untrusted_ca(checker_environment):
    log_path = os.path.join(checker_environment["work"], "untrusted.log")
    with open(log_path, "w") as f:
        f.write("card=1111-2222-3333-4444\n")

    result = run([
        checker_environment["binary"],
        checker_environment["rogue_leaf"],
        checker_environment["trusted_cert"],
        log_path,
    ])
    assert result.returncode != 0, "A leaf signed by a different CA was accepted."
    assert result.stdout.strip() or result.stderr.strip(), "Certificate failure did not print an error."


def test_rejects_wrong_dns_name(checker_environment):
    log_path = os.path.join(checker_environment["work"], "wrong-dns.log")
    with open(log_path, "w") as f:
        f.write("card=5555-6666-7777-8888\n")

    result = run([
        checker_environment["binary"],
        checker_environment["wrong_dns_leaf"],
        checker_environment["trusted_cert"],
        log_path,
    ])
    assert result.returncode != 0, "A certificate for the wrong DNS name was accepted."
    assert result.stdout.strip() or result.stderr.strip(), "Certificate failure did not print an error."


def test_rejects_wrong_root_argument(checker_environment):
    log_path = os.path.join(checker_environment["work"], "wrong-root.log")
    with open(log_path, "w") as f:
        f.write("card=2222-3333-4444-5555\n")

    result = run([
        checker_environment["binary"],
        checker_environment["valid_leaf"],
        checker_environment["rogue_cert"],
        log_path,
    ])
    assert result.returncode != 0, "The checker did not enforce the provided root certificate."
    assert result.stdout.strip() or result.stderr.strip(), "Certificate failure did not print an error."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
