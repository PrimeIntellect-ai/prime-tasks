#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
import uuid
import pytest

RECOVERED_DIR = "/home/user/operator/recovered"
MANIFEST_0 = os.path.join(RECOVERED_DIR, "manifest_0.yaml")
MANIFEST_1 = os.path.join(RECOVERED_DIR, "manifest_1.yaml")
SERVE_SCRIPT = "/home/user/operator/serve.py"
CERT_FILE = "/home/user/operator/cert.pem"
KEY_FILE = "/home/user/operator/key.pem"
PORT = 8443

EXPECTED_MANIFEST_0 = """apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
"""

EXPECTED_MANIFEST_1 = """apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
"""


def insecure_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def fetch(path, timeout=5):
    url = f"https://127.0.0.1:{PORT}/{path}"
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=insecure_context()),
    )
    with opener.open(url, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def listening_socket_inodes(ipv4_wildcard_only=False):
    found = set()
    tables = ["/proc/net/tcp"] if ipv4_wildcard_only else ["/proc/net/tcp", "/proc/net/tcp6"]
    for table in tables:
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            address, port_hex = fields[1].rsplit(":", 1)
            if int(port_hex, 16) != PORT:
                continue
            if ipv4_wildcard_only and address != "00000000":
                continue
            found.add(fields[9])
    return found


def owners_of_inodes(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        owners.add(int(entry))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def process_runs_serve_script(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except (FileNotFoundError, PermissionError, OSError):
        return False

    expected = os.path.realpath(SERVE_SCRIPT)
    for arg in argv:
        if arg == SERVE_SCRIPT:
            return True
        if arg.endswith("serve.py"):
            candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
            if os.path.realpath(candidate) == expected:
                return True
    return False


def wait_for_ipv4_wildcard_server(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        inodes = listening_socket_inodes(ipv4_wildcard_only=True)
        owners = owners_of_inodes(inodes)
        if inodes and any(process_runs_serve_script(pid) for pid in owners):
            try:
                status, _ = fetch("manifest_0.yaml", timeout=1)
                if status == 200:
                    return
            except Exception as exc:
                last_error = exc
        time.sleep(0.1)
    pytest.fail(f"serve.py did not start an HTTPS listener on 0.0.0.0:{PORT}: {last_error}")


def stop_existing_listeners():
    owners = owners_of_inodes(listening_socket_inodes())
    assert 1 not in owners, "Refusing to terminate PID 1, which unexpectedly owns port 8443"
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline and listening_socket_inodes():
        time.sleep(0.1)

    for pid in owners_of_inodes(listening_socket_inodes()):
        if pid > 1:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    deadline = time.time() + 2
    while time.time() < deadline and listening_socket_inodes():
        time.sleep(0.1)
    assert not listening_socket_inodes(), "Could not free port 8443 before executing serve.py"


def peer_certificate_der():
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as raw:
        with insecure_context().wrap_socket(raw, server_hostname="localhost") as tls:
            return tls.getpeercert(binary_form=True)


def test_recovered_directory_exists():
    assert os.path.isdir(RECOVERED_DIR), f"Directory {RECOVERED_DIR} does not exist."


def test_manifest_files_exist_and_correct():
    assert os.path.isfile(MANIFEST_0), f"File {MANIFEST_0} is missing."
    assert os.path.isfile(MANIFEST_1), f"File {MANIFEST_1} is missing."

    with open(MANIFEST_0, "r") as f:
        content_0 = f.read()
    with open(MANIFEST_1, "r") as f:
        content_1 = f.read()

    assert content_0.strip() == EXPECTED_MANIFEST_0.strip(), f"Content of {MANIFEST_0} does not match expected output."
    assert content_1.strip() == EXPECTED_MANIFEST_1.strip(), f"Content of {MANIFEST_1} does not match expected output."


def test_serve_script_exists():
    assert os.path.isfile(SERVE_SCRIPT), f"Script {SERVE_SCRIPT} is missing."


def test_https_server_running_and_serving_files():
    try:
        status, body = fetch("manifest_0.yaml")
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert body.strip() == EXPECTED_MANIFEST_0.strip(), "HTTPS server did not return the correct content for manifest_0.yaml."
    except Exception as e:
        pytest.fail(f"Failed to fetch from HTTPS server on port 8443: {e}")


def test_running_server_is_serve_script_on_ipv4_wildcard():
    inodes = listening_socket_inodes(ipv4_wildcard_only=True)
    assert inodes, f"No process is listening on 0.0.0.0:{PORT}"
    owners = owners_of_inodes(inodes)
    assert owners, "Could not identify the process owning the HTTPS listener"
    assert any(process_runs_serve_script(pid) for pid in owners), \
        "The 0.0.0.0:8443 listener is not owned by a process running /home/user/operator/serve.py"


def test_execute_serve_script_and_verify_full_contract():
    with open(SERVE_SCRIPT, "r", errors="replace") as f:
        source = f.read()
    assert "cert.pem" in source and "key.pem" in source, \
        "serve.py must load the provided cert.pem and key.pem"

    stop_existing_listeners()
    proc = subprocess.Popen(
        [sys.executable, SERVE_SCRIPT],
        cwd="/home/user/operator",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    wait_for_ipv4_wildcard_server()

    # A fresh unpredictable file proves the executed server serves the recovered
    # directory rather than returning a hardcoded manifest response.
    filename = f"verifier_probe_{uuid.uuid4().hex}.txt"
    probe_path = os.path.join(RECOVERED_DIR, filename)
    probe_body = f"probe-{uuid.uuid4().hex}\n"
    try:
        with open(probe_path, "w") as f:
            f.write(probe_body)
        status, body = fetch(filename)
        assert status == 200
        assert body == probe_body, "serve.py is not serving files from the recovered directory"

        status, body = fetch("manifest_1.yaml")
        assert status == 200
        assert body.strip() == EXPECTED_MANIFEST_1.strip()

        with open(CERT_FILE, "r") as f:
            expected_der = ssl.PEM_cert_to_DER_cert(f.read())
        assert peer_certificate_der() == expected_der, \
            "The HTTPS server is not presenting the provided cert.pem"

        cert_pubkey = subprocess.check_output(
            ["openssl", "x509", "-in", CERT_FILE, "-pubkey", "-noout"],
            stderr=subprocess.DEVNULL,
        )
        key_pubkey = subprocess.check_output(
            ["openssl", "pkey", "-in", KEY_FILE, "-pubout"],
            stderr=subprocess.DEVNULL,
        )
        assert cert_pubkey == key_pubkey, "The provided key.pem does not match the certificate used by the server"
    finally:
        try:
            os.unlink(probe_path)
        except FileNotFoundError:
            pass

    # Do not terminate proc: the instruction requires the server to remain active.
    assert proc.poll() is None or listening_socket_inodes(), "serve.py did not leave the HTTPS server active"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
