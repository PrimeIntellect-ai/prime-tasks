#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import sys
import time
import signal
import socket
import secrets
import tarfile
import subprocess
import urllib.error
import urllib.request
import pytest

BACKUP = "/home/user/backup.tar.gz"
DASHBOARDS = "/home/user/dashboards"
CERT = "/home/user/certs/cert.pem"
KEY = "/home/user/certs/key.pem"
SCRIPT = "/home/user/serve_metrics.py"
EXPECTED_DASHBOARD = b'{"dashboard": "system_overview", "panels": 4}\n'
EXPECTED_METRIC = "cpu_usage_percent 45.2"


def https_get(path, timeout=5):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://localhost:8443/" + path.lstrip("/"))
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
        return response.status, response.read()


def listener_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        port = int(fields[1].split(":")[1], 16)
                        state = fields[3]
                        if port == 8443 and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def listener_addresses():
    addresses = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 3:
                        address, port_hex = fields[1].split(":")
                        if int(port_hex, 16) == 8443 and fields[3] == "0A":
                            addresses.append((table, address))
        except FileNotFoundError:
            pass
    return addresses


def stop_port_8443():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        inodes = listener_inodes()
        if not inodes:
            return
        pids = set()
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            fd_dir = f"/proc/{pid}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(os.path.join(fd_dir, fd))
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        pids.add(int(pid))
                        break
            except (FileNotFoundError, PermissionError):
                continue
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(1)
    assert not listener_inodes(), "Could not stop the existing listener on port 8443."


def run_checked(args, input_data=None):
    result = subprocess.run(
        args, input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(args)}\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def test_backup_tarball_exists_and_valid():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} does not exist."
    assert open(os.path.join(DASHBOARDS, "main.json"), "rb").read() == EXPECTED_DASHBOARD, \
        "The dashboard fixture was altered."

    source_files = {}
    for root, dirs, files in os.walk(DASHBOARDS):
        dirs.sort()
        files.sort()
        for filename in files:
            path = os.path.join(root, filename)
            assert os.path.isfile(path) and not os.path.islink(path), \
                f"Dashboard source contains an unsupported entry: {path}"
            rel = os.path.relpath(path, DASHBOARDS).replace(os.sep, "/")
            source_files[rel] = open(path, "rb").read()
    assert source_files == {"main.json": EXPECTED_DASHBOARD}, \
        "The dashboard directory does not match the supplied fixture."

    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("main.json") for name in names), \
                f"Backup tarball {BACKUP} does not contain 'main.json'."
            archived_files = {}
            for member in tar.getmembers():
                if member.isdir():
                    continue
                assert member.isfile(), f"Backup contains a non-file entry: {member.name}"
                name = member.name.replace("\\", "/").lstrip("/")
                while name.startswith("./"):
                    name = name[2:]
                for prefix in ("home/user/dashboards/", "dashboards/"):
                    if name.startswith(prefix):
                        name = name[len(prefix):]
                        break
                assert name and not name.startswith("../") and "/../" not in name, \
                    f"Unsafe or invalid archive member: {member.name}"
                assert name not in archived_files, f"Duplicate archive member: {name}"
                extracted = tar.extractfile(member)
                assert extracted is not None
                archived_files[name] = extracted.read()
            assert archived_files == source_files, \
                "The tarball is not an exact content backup of /home/user/dashboards/."
    except tarfile.TarError:
        pytest.fail(f"File {BACKUP} is not a valid gzip-compressed tarball.")


def test_tls_certificates_exist_and_are_correct():
    assert os.path.isfile(CERT), f"Certificate file {CERT} does not exist."
    assert os.path.isfile(KEY), f"Private key file {KEY} does not exist."

    details = run_checked(["openssl", "x509", "-in", CERT, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"]).decode()
    lines = [line.strip() for line in details.splitlines() if line.strip()]
    subject = next((line.split("=", 1)[1].strip() for line in lines if line.startswith("subject=")), None)
    issuer = next((line.split("=", 1)[1].strip() for line in lines if line.startswith("issuer=")), None)
    assert subject == issuer, "The certificate is not self-signed."
    assert subject is not None and re.search(r"(?:^|,)CN=localhost(?:,|$)", subject), \
        f"Certificate Common Name is not localhost: {subject}"
    run_checked(["openssl", "verify", "-CAfile", CERT, CERT])

    cert_public_pem = run_checked(["openssl", "x509", "-in", CERT, "-noout", "-pubkey"])
    public_details = run_checked(["openssl", "pkey", "-pubin", "-text", "-noout"], cert_public_pem).decode()
    assert "Public-Key: (2048 bit)" in public_details and "modulus:" in public_details.lower(), \
        "The certificate does not contain an RSA 2048-bit public key."

    cert_public_der = run_checked(["openssl", "pkey", "-pubin", "-outform", "DER"], cert_public_pem)
    key_public_der = run_checked(["openssl", "pkey", "-in", KEY, "-pubout", "-outform", "DER"])
    assert cert_public_der == key_public_der, "The private key does not match the certificate."


def test_https_server_serving_metrics():
    try:
        status, content = https_get("data.txt")
        assert status == 200, f"Expected HTTP status 200, got {status}"
        text = content.decode("utf-8")
        assert EXPECTED_METRIC in text, \
            f"Expected '{EXPECTED_METRIC}' in response, got: {text}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the HTTPS server at https://localhost:8443/data.txt. Is the server running? Error: {e}")
    except Exception as e:
        pytest.fail(f"An unexpected error occurred while testing the HTTPS server: {e}")


def test_required_script_restarts_and_serves_metrics_directory_with_required_tls():
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), \
        f"Required Python script {SCRIPT} does not exist as a regular file."
    run_checked([sys.executable, "-m", "py_compile", SCRIPT])

    stop_port_8443()
    process = subprocess.Popen(
        [sys.executable, SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            status, content = https_get("data.txt", timeout=1)
            if status == 200 and EXPECTED_METRIC.encode() in content:
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    else:
        pytest.fail(f"Executing {SCRIPT} did not start the required HTTPS server: {last_error}")

    addresses = listener_addresses()
    assert addresses, "The script did not leave a listener on port 8443."
    ipv4_loopback = "0100007F"
    ipv6_loopback = "00000000000000000000000001000000"
    assert all(address in (ipv4_loopback, ipv6_loopback) for _, address in addresses), \
        f"Port 8443 is not bound only to localhost: {addresses}"

    expected_der = ssl.PEM_cert_to_DER_cert(open(CERT, "r", encoding="ascii").read())
    with socket.create_connection(("localhost", 8443), timeout=5) as raw:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    assert served_der == expected_der, \
        "The HTTPS server is not presenting /home/user/certs/cert.pem."

    token = secrets.token_hex(24)
    filename = f"verifier_{secrets.token_hex(12)}.txt"
    challenge_path = os.path.join("/home/user/metrics", filename)
    with open(challenge_path, "w", encoding="utf-8") as f:
        f.write(token)
    status, content = https_get(filename)
    assert status == 200 and content.decode("utf-8") == token, \
        "The executed script is not serving files from /home/user/metrics/."
    assert listener_inodes(), "The metrics server stopped before verification completed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
