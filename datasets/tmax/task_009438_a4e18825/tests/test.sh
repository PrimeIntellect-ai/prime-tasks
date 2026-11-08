#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the ephemeral TLS service is available for active discovery tests.
/usr/local/sbin/start-upload-service >/tmp/upload-service-verifier.log 2>&1 &
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import string
import subprocess


def run_handler(filename):
    return subprocess.run(
        ["/home/user/upload_handler.sh"],
        input=("UPLOAD " + filename + "\n").encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def discover_validated_service():
    ca_path = "/home/user/ca.pem"
    assert os.path.isfile(ca_path), f"CA file {ca_path} does not exist."

    found = []
    for port in range(8000, 8011):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                pass
        except OSError:
            continue

        proc = subprocess.run(
            [
                "openssl", "s_client",
                "-connect", f"127.0.0.1:{port}",
                "-servername", "localhost",
                "-showcerts",
                "-verify_return_error",
                "-CAfile", ca_path,
            ],
            input=b"UPLOAD verifier-probe.txt\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        combined = proc.stdout + proc.stderr
        if proc.returncode != 0 or b"Verify return code: 0 (ok)" not in combined:
            continue

        match = re.search(
            br"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
            combined,
            re.S,
        )
        assert match, f"Validated TLS service on port {port} did not provide a leaf certificate."
        cert_info = subprocess.run(
            ["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
            input=match.group(0) + b"\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=True,
        ).stdout.decode("utf-8", errors="strict").strip()
        cn_match = re.search(r"(?:^|,)CN=([^,]+)", cert_info.removeprefix("subject="))
        assert cn_match, f"Leaf certificate on port {port} has no Subject CN: {cert_info}"
        found.append((port, cn_match.group(1)))

    assert len(found) == 1, f"Expected exactly one CA-validated service in ports 8000-8010, found {found}."
    return found[0]


def test_cert_cn_file():
    cert_cn_path = "/home/user/cert_cn.txt"
    assert os.path.isfile(cert_cn_path), f"File {cert_cn_path} does not exist."
    with open(cert_cn_path, "r") as f:
        content = f.read().strip()
    port, actual_cn = discover_validated_service()
    assert content == actual_cn, (
        f"Expected CN '{actual_cn}' from the CA-validated service on port {port}, "
        f"but got '{content}' in {cert_cn_path}."
    )


def test_cwe_file():
    cwe_path = "/home/user/cwe.txt"
    assert os.path.isfile(cwe_path), f"File {cwe_path} does not exist."
    with open(cwe_path, "r") as f:
        content = f.read().strip()
    assert content in ["CWE-22", "CWE-022"], f"Expected 'CWE-22', but got '{content}' in {cwe_path}."


def test_upload_handler_patched_traversal():
    script_path = "/home/user/upload_handler.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    process = subprocess.run(
        [script_path],
        input=b"UPLOAD ../../../etc/passwd\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stdout_output = process.stdout.decode("utf-8").strip()
    assert process.returncode == 1, f"Expected exit code 1 for path traversal, got {process.returncode}."
    assert "INVALID" in stdout_output, f"Expected 'INVALID' in stdout for path traversal, got '{stdout_output}'."


def test_upload_handler_patched_exact_dotdot():
    process = subprocess.run(
        ["/home/user/upload_handler.sh"],
        input=b"UPLOAD ..\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stdout_output = process.stdout.decode("utf-8").strip()
    assert process.returncode == 1, f"Expected exit code 1 for '..', got {process.returncode}."
    assert "INVALID" in stdout_output, f"Expected 'INVALID' in stdout for '..', got '{stdout_output}'."


def test_upload_handler_legitimate():
    process = subprocess.run(
        ["/home/user/upload_handler.sh"],
        input=b"UPLOAD legitimate.txt\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stdout_output = process.stdout.decode("utf-8").strip()
    assert process.returncode == 0, f"Expected exit code 0 for legitimate file, got {process.returncode}."
    expected_output = "Saving to /home/user/uploads/legitimate.txt"
    assert expected_output in stdout_output, f"Expected '{expected_output}' in stdout, got '{stdout_output}'."


def test_upload_handler_randomized_traversal_cases():
    alphabet = string.ascii_letters + string.digits
    for _ in range(12):
        left = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10) + 1))
        right = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10) + 1))
        filename = left + "../" + right
        process = run_handler(filename)
        output = process.stdout.decode("utf-8").strip()
        assert process.returncode == 1, f"Expected exit code 1 for randomized traversal {filename!r}."
        assert output == "INVALID", f"Expected only INVALID for {filename!r}, got {output!r}."


def test_upload_handler_randomized_legitimate_cases():
    alphabet = string.ascii_letters + string.digits + "._-"
    for _ in range(12):
        while True:
            filename = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(20) + 1))
            if filename != ".." and "../" not in filename:
                break
        process = run_handler(filename)
        output = process.stdout.decode("utf-8").strip()
        expected = f"Saving to /home/user/uploads/{filename}"
        assert process.returncode == 0, f"Expected exit code 0 for legitimate filename {filename!r}."
        assert output == expected, f"Expected {expected!r}, got {output!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
