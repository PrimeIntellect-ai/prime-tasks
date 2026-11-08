#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import http.client
import os
import secrets
import ssl
import subprocess
import time
import urllib.parse


def test_task_complete_marker():
    assert os.path.isfile("/home/user/task_complete"), "Task complete marker not found at /home/user/task_complete."


def test_tls_certificates():
    key_path = "/home/user/certs/server.key"
    crt_path = "/home/user/certs/server.crt"
    assert os.path.isfile(key_path), f"TLS private key not found at {key_path}."
    assert os.path.isfile(crt_path), f"TLS certificate not found at {crt_path}."

    # Keep the original CN assertion.
    out = subprocess.check_output(
        ["openssl", "x509", "-in", crt_path, "-noout", "-subject"],
        text=True,
    )
    assert "CN = localhost" in out or "CN=localhost" in out, "Certificate Common Name (CN) is not localhost."

    cert_text = subprocess.check_output(
        ["openssl", "x509", "-in", crt_path, "-noout", "-text"],
        text=True,
    )
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate public key is not RSA."
    assert "Public-Key: (2048 bit)" in cert_text, "Certificate RSA public key is not exactly 2048 bits."

    with open(key_path, "rb") as key_file:
        key_bytes = key_file.read()
    assert b"ENCRYPTED" not in key_bytes.upper(), "TLS private key is encrypted."

    key_check = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-passin", "pass:", "-check", "-noout"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert key_check.returncode == 0, f"Private key is not a valid unencrypted RSA key: {key_check.stderr}"

    key_text = subprocess.check_output(
        ["openssl", "rsa", "-in", key_path, "-passin", "pass:", "-text", "-noout"],
        text=True,
        timeout=10,
    )
    assert "Private-Key: (2048 bit" in key_text, "Private RSA key is not exactly 2048 bits."

    dates = subprocess.check_output(
        ["openssl", "x509", "-in", crt_path, "-noout", "-dates"],
        text=True,
    )
    parsed = {}
    for line in dates.splitlines():
        name, value = line.split("=", 1)
        parsed[name] = datetime.datetime.strptime(
            value, "%b %d %H:%M:%S %Y %Z"
        ).replace(tzinfo=datetime.timezone.utc)

    not_before = parsed["notBefore"]
    not_after = parsed["notAfter"]
    assert not_after - not_before == datetime.timedelta(days=365), (
        f"Certificate validity is not exactly 365 days: {not_before} to {not_after}"
    )
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_rust_server_behavior():
    build_proc = subprocess.run(
        ["cargo", "build", "--release"],
        cwd="/home/user/auth-server",
        capture_output=True,
        text=True,
    )
    assert build_proc.returncode == 0, f"Cargo build failed:\n{build_proc.stderr}"

    server_proc = subprocess.Popen(
        ["./target/release/auth-server"],
        cwd="/home/user/auth-server",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(3)

    try:
        assert server_proc.poll() is None, "Built auth server failed to start."
        ctx = ssl._create_unverified_context()

        def request(next_value):
            encoded = urllib.parse.quote(next_value, safe="")
            conn = http.client.HTTPSConnection("127.0.0.1", 8443, context=ctx, timeout=5)
            conn.request("GET", "/login?next=" + encoded)
            response = conn.getresponse()
            location = response.getheader("Location")
            csp = response.getheader("Content-Security-Policy")
            response.read()
            conn.close()
            assert csp is not None, "Content-Security-Policy header is missing from the response."
            assert csp == "default-src 'self';", f"Content-Security-Policy header is incorrect. Got: {csp}"
            return location

        # Retain the original cases while adding unpredictable cases for every
        # forbidden prefix so exact-value special casing cannot pass.
        assert request("http://evil.com") == "/dashboard"
        assert request("/profile") == "/profile"

        token = secrets.token_hex(12)
        malicious_values = [
            f"http://{token}.example/path",
            f"https://{token}.example/path",
            f"http:/{token}.example/path",
            f"https:/{token}.example/path",
        ]
        for value in malicious_values:
            location = request(value)
            assert location == "/dashboard", (
                f"Expected fallback redirect to /dashboard for malicious URL {value!r}, got {location!r}"
            )

        relative = f"/settings/{secrets.token_hex(10)}"
        assert request(relative) == relative, "A valid relative redirect was not preserved."
    finally:
        if server_proc.poll() is None:
            server_proc.terminate()
            server_proc.wait(timeout=10)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
