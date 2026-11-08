#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

EXPECTED_SOURCE = '''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Simulated CGI environment variable for an HTTP header like "X-File-Name"
    char *filename = getenv("HTTP_X_FILE_NAME");
    if (!filename) {
        fprintf(stderr, "Missing HTTP_X_FILE_NAME\\n");
        return 1;
    }

    char filepath[512];
    // Construct the upload destination from the supplied filename.
    snprintf(filepath, sizeof(filepath), "/home/user/uploads/%s", filename);

    FILE *f = fopen(filepath, "w");
    if (!f) {
        fprintf(stderr, "Cannot open file for writing\\n");
        return 1;
    }

    char buffer[1024];
    size_t bytes;
    // Read uploaded file content from stdin
    while ((bytes = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
        fwrite(buffer, 1, bytes, f);
    }
    fclose(f);

    printf("Upload complete.\\n");
    return 0;
}
'''


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def test_cwe_report():
    report_path = "/home/user/report_cwe.txt"
    assert os.path.isfile(report_path), f"CWE report file missing: {report_path}"
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert "CWE-22" in content.upper(), f"Expected CWE-22 in {report_path}, found: {content}"
    assert content.upper() == "CWE-22", f"Expected the precise CWE ID CWE-22, found: {content}"


def test_client_certificate_exists():
    cert_path = "/home/user/certs/client.crt"
    key_path = "/home/user/certs/client.key"
    assert os.path.isfile(cert_path), f"Client certificate missing: {cert_path}"
    assert os.path.isfile(key_path), f"Client key missing: {key_path}"


def test_client_certificate_subject():
    cert_path = "/home/user/certs/client.crt"
    result = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject"])
    assert result.returncode == 0, f"Failed to read certificate subject: {result.stderr}"
    assert "CN" in result.stdout and "admin_inspector" in result.stdout, \
        f"Subject does not contain CN=admin_inspector. Subject: {result.stdout}"

    exact = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert exact.returncode == 0, f"Failed to parse certificate subject: {exact.stderr}"
    subject = exact.stdout.strip().removeprefix("subject=")
    common_names = [part[3:] for part in subject.split(",") if part.startswith("CN=")]
    assert common_names == ["admin_inspector"], f"Certificate CN must be exactly admin_inspector: {exact.stdout}"


def test_client_certificate_key_and_validity():
    cert_path = "/home/user/certs/client.crt"
    key_path = "/home/user/certs/client.key"

    key_check = run(["openssl", "rsa", "-in", key_path, "-check", "-noout"])
    assert key_check.returncode == 0, f"Client key is not a valid RSA private key: {key_check.stderr}"

    key_text = run(["openssl", "pkey", "-in", key_path, "-text", "-noout"])
    assert key_text.returncode == 0, f"Failed to inspect client key: {key_text.stderr}"
    assert "(2048 bit" in key_text.stdout, "Client key must be RSA-2048"

    key_modulus = run(["openssl", "rsa", "-in", key_path, "-noout", "-modulus"])
    cert_modulus = run(["openssl", "x509", "-in", cert_path, "-noout", "-modulus"])
    assert key_modulus.returncode == 0 and cert_modulus.returncode == 0, "Failed to obtain certificate/key modulus"
    assert key_modulus.stdout.strip() == cert_modulus.stdout.strip(), "Client key does not match client certificate"

    validity = run(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "2592000"])
    assert validity.returncode == 0, "Client certificate does not remain valid for at least 30 days"


def test_client_certificate_issuer_and_verification():
    cert_path = "/home/user/certs/client.crt"
    ca_path = "/home/user/ca/ca.crt"

    result_issuer = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer"])
    assert result_issuer.returncode == 0, "Failed to read certificate issuer."
    assert "Local Root CA" in result_issuer.stdout, f"Issuer is not Local Root CA. Issuer: {result_issuer.stdout}"

    result_verify = run(["openssl", "verify", "-CAfile", ca_path, cert_path])
    assert result_verify.returncode == 0, f"Certificate verification failed: {result_verify.stderr or result_verify.stdout}"
    assert "OK" in result_verify.stdout, f"Certificate not OK: {result_verify.stdout}"


def test_compiled_handler_is_from_supplied_source():
    source_path = Path("/home/user/src/upload_handler.c")
    binary_path = Path("/home/user/bin/upload_handler")
    assert source_path.is_file(), f"Source file missing: {source_path}"
    assert source_path.read_text() == EXPECTED_SOURCE, "The supplied handler source was modified"
    assert binary_path.is_file(), f"Compiled handler missing: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Compiled handler is not executable: {binary_path}"
    assert binary_path.read_bytes()[:4] == b"\x7fELF", "Compiled handler is not an ELF executable"

    reference_path = "/tmp/upload_handler.reference"
    compiled = run(["gcc", str(source_path), "-o", reference_path])
    assert compiled.returncode == 0, f"Supplied source does not compile with GCC: {compiled.stderr}"
    assert binary_path.read_bytes() == Path(reference_path).read_bytes(), \
        "Handler artifact does not match GCC output for the supplied source"


def test_exploit_success():
    token_path = "/home/user/admin_token.txt"
    assert os.path.isfile(token_path), f"Token file missing: {token_path}"
    with open(token_path, "r") as f:
        content = f.read().strip()
    assert content == "EXPLOITED", f"Token file was not successfully exploited. Content found: {content}"

    # Reset the target, then require the submitted compiled CGI artifact itself to
    # reproduce the requested traversal using its environment and standard input.
    Path(token_path).write_text("VALID_TOKEN\n")
    env = os.environ.copy()
    env["HTTP_X_FILE_NAME"] = "../admin_token.txt"
    executed = subprocess.run(
        ["/home/user/bin/upload_handler"],
        input=b"EXPLOITED",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=10,
    )
    assert executed.returncode == 0, f"Handler execution failed: {executed.stderr.decode(errors='replace')}"
    assert Path(token_path).read_bytes() in (b"EXPLOITED", b"EXPLOITED\n"), \
        "Executing the compiled handler did not overwrite admin_token.txt with EXPLOITED"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
