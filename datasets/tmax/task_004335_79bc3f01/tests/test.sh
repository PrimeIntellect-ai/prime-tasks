#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import os
import re
import secrets
import socket
import ssl
import subprocess
import time

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

SERVER_URL = "https://127.0.0.1:8443/auth"
CORRECT_TOKEN = "TrUSt_N0_1_XyZ99"
WRONG_TOKEN = "wrong_token"
LOG_FILE = "/home/user/auth_audit.log"
CERT_FILE = "/home/user/server.crt"
KEY_FILE = "/home/user/server.key"
SERVER_FILE = "/home/user/secure_auth_server.py"
LOG_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] 127\.0\.0\.1 - Action: (ALLOW|DENY)$")


def run_openssl(*args, input_data=None):
    result = subprocess.run(
        ["openssl", *args], input=input_data, capture_output=True, check=False
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def log_size():
    return os.path.getsize(LOG_FILE) if os.path.exists(LOG_FILE) else 0


def assert_new_log_entry(start, expected_action):
    deadline = time.time() + 2
    added = b""
    while time.time() < deadline:
        if os.path.exists(LOG_FILE):
            current = os.path.getsize(LOG_FILE)
            assert current >= start, "Audit log was truncated while handling a request"
            with open(LOG_FILE, "rb") as f:
                f.seek(start)
                added = f.read()
            if added.endswith(b"\n"):
                break
        time.sleep(0.05)

    try:
        text = added.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"New audit log data is not UTF-8: {exc}")

    lines = text.splitlines()
    assert len(lines) == 1, f"Expected exactly one audit line for one request, got: {lines!r}"
    match = LOG_RE.fullmatch(lines[0])
    assert match, f"Audit line has the wrong format: {lines[0]!r}"
    assert match.group(2) == expected_action, (
        f"Expected audit action {expected_action}, got {match.group(2)}"
    )
    try:
        datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    except ValueError as exc:
        pytest.fail(f"Audit log timestamp is invalid: {exc}")


def post_and_check(payload, expected_code, expected_status, expected_action):
    start = log_size()
    try:
        response = requests.post(SERVER_URL, json=payload, verify=False, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTPS server at {SERVER_URL}: {exc}")

    assert response.status_code == expected_code, (
        f"Expected HTTP {expected_code}, got {response.status_code}"
    )
    try:
        json_data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert json_data.get("status") == expected_status, (
        f"Expected status {expected_status!r}, got {json_data.get('status')!r}"
    )
    assert_new_log_entry(start, expected_action)


def listening_process_cmdlines():
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            if local_address.upper() == "0100007F:20FB" and state == "0A":
                inodes.add(inode)

    commands = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_listener = any(
                os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{inode}]"
                for fd in os.listdir(fd_dir)
                for inode in inodes
            )
            if owns_listener:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    commands.append(f.read().replace(b"\0", b" ").decode(errors="replace"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return inodes, commands


def test_certificates_exist():
    """Verify certificate/key existence and all required cryptographic properties."""
    assert os.path.exists(CERT_FILE), f"Certificate file missing: {CERT_FILE}"
    assert os.path.exists(KEY_FILE), f"Private key file missing: {KEY_FILE}"
    assert os.path.isfile(CERT_FILE), f"Certificate is not a regular file: {CERT_FILE}"
    assert os.path.isfile(KEY_FILE), f"Private key is not a regular file: {KEY_FILE}"

    cert_text = run_openssl("x509", "-in", CERT_FILE, "-noout", "-text").decode()
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate key is not RSA"
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), "RSA certificate key is not 2048-bit"
    run_openssl("x509", "-in", CERT_FILE, "-noout", "-checkend", "0")
    run_openssl("pkey", "-in", KEY_FILE, "-check", "-noout")

    subject = run_openssl("x509", "-in", CERT_FILE, "-noout", "-subject", "-nameopt", "RFC2253").decode().strip()
    issuer = run_openssl("x509", "-in", CERT_FILE, "-noout", "-issuer", "-nameopt", "RFC2253").decode().strip()
    assert subject.partition("=")[2] == issuer.partition("=")[2], "Certificate is not self-issued"
    run_openssl("verify", "-CAfile", CERT_FILE, CERT_FILE)

    cert_pub = run_openssl("x509", "-in", CERT_FILE, "-pubkey", "-noout")
    key_pub = run_openssl("pkey", "-in", KEY_FILE, "-pubout")
    cert_der = run_openssl("pkey", "-pubin", "-outform", "DER", input_data=cert_pub)
    key_der = run_openssl("pkey", "-pubin", "-outform", "DER", input_data=key_pub)
    assert cert_der == key_der, "Certificate and private key do not form a pair"

    context = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="127.0.0.1") as tls_socket:
            peer_der = tls_socket.getpeercert(binary_form=True)
    with open(CERT_FILE, "r") as f:
        file_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert peer_der == file_der, "The service is not using /home/user/server.crt"


def test_server_artifact_is_running():
    assert os.path.isfile(SERVER_FILE), f"Server source file missing: {SERVER_FILE}"
    with open(SERVER_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "Server source file is empty"
    ast.parse(source, filename=SERVER_FILE)

    inodes, commands = listening_process_cmdlines()
    assert inodes, "No process is listening on 127.0.0.1:8443"
    assert any(SERVER_FILE in command and "python" in command.lower() for command in commands), (
        f"The listener is not the required Python server artifact; listener commands: {commands!r}"
    )


def test_auth_endpoint_success():
    """Test the HTTPS server with the correct token."""
    post_and_check({"token": CORRECT_TOKEN}, 200, "success", "ALLOW")


def test_auth_endpoint_forbidden():
    """Test the HTTPS server with the original fixed incorrect token."""
    post_and_check({"token": WRONG_TOKEN}, 403, "forbidden", "DENY")


def test_random_invalid_and_missing_tokens_are_forbidden():
    random_tokens = []
    while len(random_tokens) < 5:
        token = secrets.token_urlsafe(24)
        if token not in (CORRECT_TOKEN, WRONG_TOKEN):
            random_tokens.append(token)
    for token in random_tokens:
        post_and_check({"token": token}, 403, "forbidden", "DENY")
    post_and_check({}, 403, "forbidden", "DENY")


def test_auth_audit_log():
    """Retain the original ALLOW and DENY audit-log assertions."""
    assert os.path.exists(LOG_FILE), f"Audit log file missing: {LOG_FILE}"
    with open(LOG_FILE, "r") as f:
        log_content = f.read()

    allow_pattern = r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] 127\.0\.0\.1 - Action: ALLOW"
    deny_pattern = r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] 127\.0\.0\.1 - Action: DENY"
    assert re.search(allow_pattern, log_content), "Audit log is missing the required ALLOW entry format."
    assert re.search(deny_pattern, log_content), "Audit log is missing the required DENY entry format."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
