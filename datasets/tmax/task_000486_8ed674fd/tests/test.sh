#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import socket
import ssl
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

APP = "/home/user/app"
FSTAB = "/home/user/config.fstab"
USERS_URL = "https://127.0.0.1:8443/users.json"


def tls_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def server_pids():
    try:
        output = subprocess.check_output(["pgrep", "-f", "server.py"], text=True).strip()
    except subprocess.CalledProcessError:
        return []
    return [int(p) for p in output.splitlines() if p.strip()]


def fetch(url, timeout=5):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=tls_context(), timeout=timeout) as response:
        return response.status, response.read()


def wait_for_content(url, expected, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = fetch(url, timeout=1)
            if status == 200 and body == expected:
                return
            last_error = AssertionError(f"Got status {status} and body {body!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    raise AssertionError(f"Server did not serve expected content at {url}: {last_error}")


def test_permissions():
    """Test that the permissions of the accounts_data directory are exactly 0700."""
    path = "/home/user/accounts_data"
    assert os.path.exists(path), f"Directory {path} does not exist."
    mode = stat.S_IMODE(os.stat(path).st_mode)
    assert mode == 0o700, f"Expected permissions 0700 for {path}, but got {oct(mode)}."


def test_artifacts_exist():
    for name in ("server.py", "supervisor.py"):
        path = os.path.join(APP, name)
        assert os.path.isfile(path), f"Required script {path} does not exist or is not a regular file."


def test_certificates():
    """Validate the requested self-signed RSA-2048 certificate and unencrypted key."""
    cert_path = os.path.join(APP, "cert.pem")
    key_path = os.path.join(APP, "key.pem")
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."

    subject = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"],
        text=True,
    ).strip()
    issuer = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"],
        text=True,
    ).strip()
    assert subject == "subject=CN=localhost", f"Unexpected certificate subject: {subject}"
    assert issuer == "issuer=CN=localhost", f"Certificate is not self-signed as CN=localhost: {issuer}"

    cert_text = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True
    )
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate key is not RSA."
    assert "Public-Key: (2048 bit)" in cert_text, "Certificate RSA key is not 2048 bits."
    subprocess.check_call(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    with open(key_path, "rb") as f:
        key_bytes = f.read()
    assert b"ENCRYPTED PRIVATE KEY" not in key_bytes, "Private key is encrypted."
    key_check = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-noout"],
        input=b"",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert key_check.returncode == 0, "Private key is invalid or requires a passphrase."

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    cert_pub_der = subprocess.check_output(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub
    )
    key_pub_der = subprocess.check_output(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]
    )
    assert cert_pub_der == key_pub_der, "Certificate and private key do not match."


def test_https_server():
    """Test that HTTPS is running, serves the original data, and uses cert.pem."""
    try:
        status, body = fetch(USERS_URL)
        assert status == 200
        data = json.loads(body.decode("utf-8"))
        assert data == {"users": ["admin", "guest"]}, "Server did not return the expected JSON data."
    except Exception as exc:
        pytest.fail(f"HTTPS server check failed: {exc}")

    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with tls_context().wrap_socket(raw, server_hostname="localhost") as connection:
            served_der = connection.getpeercert(binary_form=True)
    with open(os.path.join(APP, "cert.pem"), "r") as f:
        file_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == file_der, "The HTTPS server is not using /home/user/app/cert.pem."


def test_supervisor():
    """Test that the supervisor restarts server.py and logs the event."""
    pids = server_pids()
    assert pids, "server.py is not running."
    pid = pids[0]

    try:
        os.kill(pid, 9)
    except OSError as exc:
        pytest.fail(f"Failed to kill server.py (PID {pid}): {exc}")

    time.sleep(3)
    new_pids = server_pids()
    assert new_pids, "server.py did not restart after being killed."
    assert pid not in new_pids, "server.py was not actually killed."

    log_path = os.path.join(APP, "supervisor.log")
    assert os.path.isfile(log_path), f"Supervisor log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert "[RESTART]" in content, f"Supervisor log {log_path} does not contain the string '[RESTART]'."

    try:
        status, body = fetch(USERS_URL)
        assert status == 200, "Restarted server did not respond with status 200."
        data = json.loads(body.decode("utf-8"))
        assert data == {"users": ["admin", "guest"]}, "Restarted server did not return the expected JSON data."
    except Exception as exc:
        pytest.fail(f"HTTPS server not responding correctly after restart: {exc}")


def test_dynamic_fstab_directory_and_exclusive_serving():
    """Use an unpredictable mount target to ensure server.py parses fstab on startup."""
    token = secrets.token_hex(16)
    filename = f"probe-{secrets.token_hex(10)}.txt"
    expected = ("dynamic-" + secrets.token_hex(32)).encode("ascii")
    alternate = f"/home/user/accounts_dynamic_{token}"
    os.mkdir(alternate, 0o700)
    with open(os.path.join(alternate, filename), "wb") as f:
        f.write(expected)

    with open(FSTAB, "rb") as f:
        original_fstab = f.read()
    lines = original_fstab.decode("utf-8").splitlines()
    replaced = False
    new_lines = []
    for line in lines:
        if line.startswith("accounts_mount"):
            new_lines.append(f"accounts_mount {alternate} ext4 defaults 0 0")
            replaced = True
        else:
            new_lines.append(line)
    assert replaced, "accounts_mount entry is missing from config.fstab."

    try:
        with open(FSTAB, "w") as f:
            f.write("\n".join(new_lines) + "\n")

        pids = server_pids()
        assert pids, "server.py is not running before the dynamic fstab test."
        os.kill(pids[0], 9)

        probe_url = f"https://127.0.0.1:8443/{filename}"
        wait_for_content(probe_url, expected)

        with pytest.raises(urllib.error.HTTPError) as exc_info:
            fetch(USERS_URL)
        assert exc_info.value.code == 404, "Server exposed a file outside the configured mount directory."
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
        pids = server_pids()
        if pids:
            try:
                os.kill(pids[0], 9)
            except ProcessLookupError:
                pass
        wait_for_content(USERS_URL, b'{"users": ["admin", "guest"]}\n')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
