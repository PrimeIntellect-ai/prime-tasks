#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import ipaddress
import os
import re
import secrets
import socket
import ssl
import subprocess
import urllib.error
import urllib.request

import pytest

CRT_PATH = "/home/user/tls/server.crt"
KEY_PATH = "/home/user/tls/server.key"
SCRIPT_PATH = "/home/user/run_https.py"


def run_checked(args, input_data=None):
    return subprocess.run(
        args,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=10,
    ).stdout


def fetch(url):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        return response.status, response.read()


def parse_openssl_time(value):
    return datetime.datetime.strptime(value, "%b %d %H:%M:%S %Y GMT").replace(
        tzinfo=datetime.timezone.utc
    )


def listening_sockets_9443():
    found = []
    for table, family in (("/proc/net/tcp", socket.AF_INET), ("/proc/net/tcp6", socket.AF_INET6)):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                local_hex, port_hex = fields[1].split(":")
                if int(port_hex, 16) != 9443 or fields[3] != "0A":
                    continue
                raw = bytes.fromhex(local_hex)
                if family == socket.AF_INET:
                    address = socket.inet_ntop(family, raw[::-1])
                else:
                    raw = b"".join(raw[i:i + 4][::-1] for i in range(0, 16, 4))
                    address = socket.inet_ntop(family, raw)
                found.append((address, fields[9]))
    return found


def pids_for_socket_inode(inode):
    result = []
    needle = f"socket:[{inode}]"
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == needle:
                        result.append(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return result


def process_runs_script(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return False

    if not executable.startswith("python"):
        return False

    for arg in args:
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        try:
            if os.path.samefile(candidate, SCRIPT_PATH):
                return True
        except OSError:
            pass
    return False


def test_shared_assets_logo():
    logo_path = "/home/user/shared_assets/logo.png"
    assert os.path.isfile(logo_path), f"File {logo_path} does not exist."
    with open(logo_path, "r") as f:
        content = f.read()
    assert content == "FAKE PNG DATA", f"Expected 'FAKE PNG DATA' in {logo_path}, got '{content}'"


def test_app_content_symlink():
    symlink_path = "/home/user/app_content/assets"
    target_path = "/home/user/shared_assets"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    actual_target = os.readlink(symlink_path)
    assert actual_target == target_path, (
        f"Expected symlink {symlink_path} to point to {target_path}, but it points to {actual_target}."
    )


def test_tls_certificates_exist_and_are_correct():
    assert os.path.isfile(CRT_PATH), f"TLS certificate {CRT_PATH} does not exist."
    assert os.path.isfile(KEY_PATH), f"TLS private key {KEY_PATH} does not exist."

    cert_text = run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-text"]).decode()
    cert_pub_text = run_checked(
        ["openssl", "x509", "-in", CRT_PATH, "-pubkey", "-noout"]
    )
    cert_pub_details = run_checked(
        ["openssl", "pkey", "-pubin", "-text", "-noout"], cert_pub_text
    ).decode()
    assert "Public-Key: (2048 bit)" in cert_pub_details, "Certificate public key is not RSA-2048."
    assert "Modulus:" in cert_pub_details and "Exponent:" in cert_pub_details, "Certificate key is not RSA."

    subject = run_checked(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-subject", "-nameopt", "RFC2253"]
    ).decode().strip()
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject.removeprefix("subject=")), (
        f"Certificate subject CN is not localhost: {subject}"
    )

    issuer = run_checked(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-issuer", "-nameopt", "RFC2253"]
    ).decode().strip()
    assert subject.removeprefix("subject=") == issuer.removeprefix("issuer="), "Certificate is not self-signed."
    run_checked(["openssl", "verify", "-CAfile", CRT_PATH, CRT_PATH])

    dates = run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-dates"]).decode().splitlines()
    values = dict(line.split("=", 1) for line in dates)
    not_before = parse_openssl_time(values["notBefore"])
    not_after = parse_openssl_time(values["notAfter"])
    assert not_after - not_before == datetime.timedelta(days=365), "Certificate validity is not exactly 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."

    with open(KEY_PATH, "rb") as f:
        key_bytes = f.read()
    assert b"ENCRYPTED" not in key_bytes.upper(), "Private key is encrypted."
    run_checked(["openssl", "rsa", "-in", KEY_PATH, "-check", "-noout"])
    key_details = run_checked(["openssl", "pkey", "-in", KEY_PATH, "-text", "-noout"]).decode()
    assert "Private-Key: (2048 bit" in key_details, "Private key is not RSA-2048."

    cert_pub_der = run_checked(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], cert_pub_text
    )
    key_pub_der = run_checked(
        ["openssl", "pkey", "-in", KEY_PATH, "-pubout", "-outform", "DER"]
    )
    assert hashlib.sha256(cert_pub_der).digest() == hashlib.sha256(key_pub_der).digest(), (
        "Private key does not match the certificate."
    )


def test_https_script_is_the_localhost_listener():
    assert os.path.isfile(SCRIPT_PATH), f"Python server script {SCRIPT_PATH} does not exist."
    subprocess.run(
        ["python3", "-m", "py_compile", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=10,
    )

    listeners = listening_sockets_9443()
    assert listeners, "No process is listening on port 9443."
    listener_pids = set()
    for address, inode in listeners:
        assert ipaddress.ip_address(address).is_loopback, (
            f"Port 9443 is listening on non-localhost address {address}."
        )
        listener_pids.update(pids_for_socket_inode(inode))
    assert listener_pids, "Could not identify the process listening on port 9443."
    assert any(process_runs_script(pid) for pid in listener_pids), (
        f"The port 9443 listener is not the Python process running {SCRIPT_PATH}."
    )


def test_server_uses_generated_certificate():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("localhost", 9443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="localhost") as tls_socket:
            presented_der = tls_socket.getpeercert(binary_form=True)
    expected_der = run_checked(["openssl", "x509", "-in", CRT_PATH, "-outform", "DER"])
    assert presented_der == expected_der, "The HTTPS endpoint is not serving /home/user/tls/server.crt."


def test_https_server_reachable_and_serves_app_content():
    url = "https://localhost:9443/assets/logo.png"
    try:
        status, content = fetch(url)
        assert status == 200, f"Expected HTTP status 200, got {status}"
        assert content.decode("utf-8") == "FAKE PNG DATA", (
            f"Expected response content 'FAKE PNG DATA', got '{content.decode('utf-8')}'"
        )

        token = secrets.token_hex(16)
        challenge_name = f"verifier_{token}.txt"
        challenge_path = os.path.join("/home/user/app_content", challenge_name)
        challenge_data = secrets.token_bytes(32)
        try:
            with open(challenge_path, "wb") as f:
                f.write(challenge_data)
            challenge_status, served_data = fetch(f"https://localhost:9443/{challenge_name}")
            assert challenge_status == 200
            assert served_data == challenge_data, "Server is not serving files from /home/user/app_content."
        finally:
            try:
                os.unlink(challenge_path)
            except FileNotFoundError:
                pass
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the HTTPS server at {url}: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
