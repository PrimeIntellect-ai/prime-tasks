#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time

import pytest

CERT_DIR = "/home/user/certs"
CERT_PATH = CERT_DIR + "/cert.pem"
KEY_PATH = CERT_DIR + "/key.pem"
SCRIPT_PATH = "/home/user/run_exploit.py"
LOOT_PATH = "/home/user/loot.txt"
APP_PATH = "/home/user/vulnerable_app.py"
SECRET_PATH = "/home/user/secret.txt"
MARKER_PATH = "/tmp/vulnerable_app_invocation.json"


def run_checked(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def port_is_open():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", 8443)) == 0


def test_certs_directory_exists_and_permissions():
    path = CERT_DIR
    assert os.path.isdir(path), f"Directory {path} does not exist."

    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o700, f"Directory {path} has permissions {oct(mode)}, expected 0o700."


def test_cert_and_key_files_exist():
    cert_path = CERT_PATH
    key_path = KEY_PATH

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."


def test_certificate_and_key_are_valid_and_matching():
    run_checked(["openssl", "x509", "-in", CERT_PATH, "-noout"])
    run_checked(["openssl", "pkey", "-in", KEY_PATH, "-noout", "-check"])
    run_checked(["openssl", "verify", "-CAfile", CERT_PATH, CERT_PATH])

    details = run_checked([
        "openssl", "x509", "-in", CERT_PATH, "-noout",
        "-subject", "-issuer", "-dates"
    ], text=True).stdout
    fields = {}
    for line in details.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key.strip()] = value.strip()

    assert fields.get("subject") == fields.get("issuer"), "Certificate is not self-signed."
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(fields["notBefore"], fmt)
    not_after = datetime.datetime.strptime(fields["notAfter"], fmt)
    lifetime = (not_after - not_before).total_seconds()
    assert abs(lifetime - 365 * 24 * 60 * 60) <= 60, "Certificate is not valid for 365 days."
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    assert not_before <= now <= not_after, "Certificate is not currently valid."

    key_info = run_checked([
        "openssl", "pkey", "-in", KEY_PATH, "-text", "-noout"
    ], text=True).stdout
    assert re.search(r"(?:Private-Key|RSA Public-Key): \(2048 bit", key_info), \
        "Private key is not a 2048-bit RSA key."

    key_public = run_checked([
        "openssl", "pkey", "-in", KEY_PATH, "-pubout", "-outform", "DER"
    ]).stdout
    cert_public_pem = run_checked([
        "openssl", "x509", "-in", CERT_PATH, "-pubkey", "-noout"
    ]).stdout
    cert_public = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_public_pem, check=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    ).stdout
    assert key_public == cert_public, "Certificate and private key do not match."


def test_run_exploit_script_exists():
    path = SCRIPT_PATH
    assert os.path.isfile(path), f"Python script {path} does not exist."


def test_script_uses_subprocess_module():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    module_aliases = set()
    imported_functions = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess":
                    module_aliases.add(alias.asname or "subprocess")
        elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            imported_functions.update(alias.asname or alias.name for alias in node.names)

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            used |= node.func.value.id in module_aliases
        elif isinstance(node.func, ast.Name):
            used |= node.func.id in imported_functions
    assert used, "run_exploit.py does not invoke the vulnerable app using subprocess."


def test_loot_file_exists_and_permissions():
    path = LOOT_PATH
    assert os.path.isfile(path), f"Loot file {path} does not exist."

    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o600, f"Loot file {path} has permissions {oct(mode)}, expected 0o600."


def test_loot_file_content():
    path = LOOT_PATH
    assert os.path.isfile(path), f"Loot file {path} does not exist."

    expected_content = (
        "User profile information:\n"
        "Name: John Doe\n"
        "Role: Administrator\n"
        "Account: XXXX-XXXX-XXXX-XXXX\n"
        "API_KEY: 8f92j-29eu2-9283h\n"
        "Account2: XXXX-XXXX-XXXX-XXXX"
    )

    with open(path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, "The content of loot.txt does not match the expected redacted output."


def test_exploit_executes_over_https_redacts_and_stops_server():
    assert not port_is_open(), "Port 8443 is already serving; the prior exploit server was not shut down."

    with open(APP_PATH, "rb") as f:
        original_app = f.read()
    app_mode = stat.S_IMODE(os.stat(APP_PATH).st_mode)
    with open(SECRET_PATH, "rb") as f:
        original_secret = f.read()
    secret_mode = stat.S_IMODE(os.stat(SECRET_PATH).st_mode)
    loot_existed = os.path.exists(LOOT_PATH)
    original_loot = None
    original_loot_mode = None
    if loot_existed:
        with open(LOOT_PATH, "rb") as f:
            original_loot = f.read()
        original_loot_mode = stat.S_IMODE(os.stat(LOOT_PATH).st_mode)

    token = os.urandom(12).hex()
    dynamic_secret = (
        f"Dynamic verification {token}\n"
        "Primary: 3141-5926-5358-9793\n"
        "Leave-near-match: 1234-5678-9012-345X\n"
        "Secondary: 2718-2818-2845-9045\n"
    )

    instrumented_app = r'''#!/usr/bin/env python3
import hashlib
import http.client
import json
import os
import ssl
import sys

if len(sys.argv) != 2 or sys.argv[1] != "https://localhost:8443/":
    print("Usage: vulnerable_app.py <url>")
    raise SystemExit(2)

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
conn = http.client.HTTPSConnection("localhost", 8443, context=ctx, timeout=5)
conn.request("GET", "/")
resp = conn.getresponse()
der = conn.sock.getpeercert(binary_form=True)
body = resp.read()
conn.close()
with open("/home/user/certs/cert.pem", "r", encoding="ascii") as f:
    expected_der = ssl.PEM_cert_to_DER_cert(f.read())
if der != expected_der:
    raise SystemExit("HTTPS server did not present cert.pem")
payload = json.loads(body.decode("utf-8"))
if payload.get("file_to_read") != "/home/user/secret.txt":
    raise SystemExit("Incorrect exploit payload")
with open("/tmp/vulnerable_app_invocation.json", "w", encoding="utf-8") as f:
    json.dump({"url": sys.argv[1], "path": payload["file_to_read"],
               "certificate_sha256": hashlib.sha256(der).hexdigest()}, f)
with open(payload["file_to_read"], "r", encoding="utf-8") as f:
    print(f.read())
'''

    try:
        if os.path.exists(MARKER_PATH):
            os.unlink(MARKER_PATH)
        with open(SECRET_PATH, "w", encoding="utf-8") as f:
            f.write(dynamic_secret)
        os.chmod(SECRET_PATH, secret_mode)
        with open(APP_PATH, "w", encoding="utf-8") as f:
            f.write(instrumented_app)
        os.chmod(APP_PATH, 0o755)
        if os.path.exists(LOOT_PATH):
            os.unlink(LOOT_PATH)

        completed = subprocess.run(
            ["python3", SCRIPT_PATH], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert completed.returncode == 0, (
            f"run_exploit.py failed with code {completed.returncode}:\n"
            f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
        )
        assert os.path.isfile(MARKER_PATH), "The vulnerable app was not invoked successfully."
        with open(MARKER_PATH, "r", encoding="utf-8") as f:
            marker = json.load(f)
        assert marker["url"] == "https://localhost:8443/"
        assert marker["path"] == SECRET_PATH

        assert os.path.isfile(LOOT_PATH), "Executing run_exploit.py did not create loot.txt."
        assert stat.S_IMODE(os.stat(LOOT_PATH).st_mode) == 0o600
        with open(LOOT_PATH, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        expected = re.sub(r"\d{4}-\d{4}-\d{4}-\d{4}",
                          "XXXX-XXXX-XXXX-XXXX", dynamic_secret).strip()
        assert actual == expected, "Dynamic vulnerable-app output was not captured and correctly redacted."

        time.sleep(0.5)
        assert not port_is_open(), "The HTTPS server remained running after the exploit completed."
    finally:
        with open(APP_PATH, "wb") as f:
            f.write(original_app)
        os.chmod(APP_PATH, app_mode)
        with open(SECRET_PATH, "wb") as f:
            f.write(original_secret)
        os.chmod(SECRET_PATH, secret_mode)
        if loot_existed:
            with open(LOOT_PATH, "wb") as f:
                f.write(original_loot)
            os.chmod(LOOT_PATH, original_loot_mode)
        elif os.path.exists(LOOT_PATH):
            os.unlink(LOOT_PATH)
        if os.path.exists(MARKER_PATH):
            os.unlink(MARKER_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
