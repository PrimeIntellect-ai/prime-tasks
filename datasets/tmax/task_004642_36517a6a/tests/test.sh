#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import signal
import socket
import ssl
import stat
import subprocess
import sys
import tarfile
import time
import uuid

import pytest

OPERATOR = "/home/user/operator.py"
CERT = "/home/user/certs/cert.pem"
KEY = "/home/user/certs/key.pem"
BACKUP = "/home/user/backups/manifests.tar.gz"
EXPECTED_STATUS = "Backup successful: manifests.tar.gz"


def listening_inodes():
    inodes = set()
    try:
        with open("/proc/net/tcp") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address, state = fields[1], fields[3]
                if local_address.endswith(":20FB") and state == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass
    return inodes


def kill_existing_8443_listeners():
    inodes = listening_inodes()
    if not inodes:
        return

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes():
        time.sleep(0.05)

    if listening_inodes():
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)


@pytest.fixture(scope="session", autouse=True)
def operator_process():
    assert os.path.isfile(OPERATOR), f"Operator script {OPERATOR} does not exist."
    assert stat.S_ISREG(os.stat(OPERATOR).st_mode), f"{OPERATOR} is not a regular file."

    with open(OPERATOR, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=OPERATOR)

    kill_existing_8443_listeners()
    assert not listening_inodes(), "Could not clear the existing listener on port 8443."

    try:
        os.unlink(BACKUP)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [sys.executable, OPERATOR],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            stdout, stderr = proc.communicate()
            pytest.fail(
                "operator.py exited before serving HTTPS.\n"
                f"stdout: {stdout.decode(errors='replace')}\n"
                f"stderr: {stderr.decode(errors='replace')}"
            )
        if os.path.isfile(BACKUP) and listening_inodes():
            try:
                with socket.create_connection(("127.0.0.1", 8443), timeout=0.5):
                    break
            except OSError:
                pass
        time.sleep(0.1)
    else:
        proc.terminate()
        pytest.fail("operator.py did not create the backup and listen on port 8443.")

    assert proc.poll() is None, "operator.py is not still running."
    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def run_openssl(*args):
    return subprocess.run(
        ["openssl", *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=True,
    ).stdout


def test_manifests_permissions():
    path = "/home/user/manifests"
    assert os.path.exists(path), f"Directory {path} does not exist."
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o700, f"Permissions for {path} are {oct(mode)}, expected 0o700."


def test_operator_uses_required_builtin_modules():
    with open(OPERATOR, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=OPERATOR)

    uses_ssl = False
    uses_http_server = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            uses_ssl |= any(alias.name == "ssl" for alias in node.names)
            uses_http_server |= any(alias.name == "http.server" for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            uses_ssl |= node.module == "ssl"
            uses_http_server |= node.module == "http.server"
            uses_http_server |= node.module == "http" and any(
                alias.name == "server" for alias in node.names
            )

    assert uses_ssl, "operator.py does not use Python's built-in ssl module."
    assert uses_http_server, "operator.py does not use Python's built-in http.server module."


def test_certs_exist_and_non_empty():
    assert os.path.isfile(CERT), f"Certificate file {CERT} does not exist."
    assert os.path.getsize(CERT) > 0, f"Certificate file {CERT} is empty."
    assert os.path.isfile(KEY), f"Key file {KEY} does not exist."
    assert os.path.getsize(KEY) > 0, f"Key file {KEY} is empty."

    run_openssl("x509", "-in", CERT, "-noout", "-checkend", "0")
    run_openssl("rsa", "-in", KEY, "-check", "-noout")

    key_text = run_openssl("pkey", "-in", KEY, "-text", "-noout").decode(errors="replace")
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text), "Private key is not 2048-bit RSA."

    cert_pub = run_openssl("x509", "-in", CERT, "-pubkey", "-noout")
    key_pub = run_openssl("pkey", "-in", KEY, "-pubout")
    assert cert_pub == key_pub, "Certificate and private key do not match."

    subject = run_openssl("x509", "-in", CERT, "-noout", "-subject").decode().partition("=")[2].strip()
    issuer = run_openssl("x509", "-in", CERT, "-noout", "-issuer").decode().partition("=")[2].strip()
    assert subject == issuer, "Certificate is not self-signed."
    run_openssl("verify", "-CAfile", CERT, CERT)


def test_backup_tarball_valid():
    assert os.path.isfile(BACKUP), f"Backup archive {BACKUP} does not exist."

    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            names = tar.getnames()
            basenames = [os.path.basename(name) for name in names]
            assert "deployment.yaml" in basenames, "deployment.yaml not found in backup archive."
            assert "service.yaml" in basenames, "service.yaml not found in backup archive."

            archived = {}
            for member in tar.getmembers():
                if member.isfile():
                    extracted = tar.extractfile(member)
                    archived.setdefault(os.path.basename(member.name), []).append(extracted.read())

            manifests = "/home/user/manifests"
            for root, _, files in os.walk(manifests):
                for filename in files:
                    path = os.path.join(root, filename)
                    with open(path, "rb") as f:
                        expected_data = f.read()
                    assert expected_data in archived.get(filename, []), (
                        f"Current manifest {path} and its contents are not present in the archive."
                    )
    except tarfile.ReadError:
        pytest.fail(f"Backup archive {BACKUP} is not a valid gzip-compressed tarball.")


def test_live_https_server_uses_generated_certificate(operator_process):
    context = ssl._create_unverified_context()
    path = "/verify-" + uuid.uuid4().hex

    with socket.create_connection(("127.0.0.1", 8443), timeout=3) as raw:
        with context.wrap_socket(raw, server_hostname="127.0.0.1") as tls:
            with open(CERT, "r", encoding="ascii") as f:
                expected_der = ssl.PEM_cert_to_DER_cert(f.read())
            assert tls.getpeercert(binary_form=True) == expected_der, (
                "HTTPS server is not presenting /home/user/certs/cert.pem."
            )
            request = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            tls.sendall(request.encode("ascii"))
            chunks = []
            while True:
                chunk = tls.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)

    response = b"".join(chunks)
    headers, separator, body = response.partition(b"\r\n\r\n")
    assert separator, "Server returned a malformed HTTP response."
    assert headers.splitlines()[0].startswith(b"HTTP/1.")
    assert b" 200 " in headers.splitlines()[0], "GET request did not return HTTP 200."
    assert body.decode("utf-8") == EXPECTED_STATUS, "HTTPS response body is incorrect."

    curl_path = "/verify-" + uuid.uuid4().hex
    curl = subprocess.run(
        ["curl", "-k", "-sS", "--max-time", "5", "-w", "\n%{http_code}",
         f"https://127.0.0.1:8443{curl_path}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=7,
        check=True,
        text=True,
    )
    body, code = curl.stdout.rsplit("\n", 1)
    assert code == "200", f"curl received HTTP status {code}, expected 200."
    assert body == EXPECTED_STATUS, "curl did not receive the exact expected response."
    assert operator_process.poll() is None, "operator.py stopped while serving requests."


def test_status_log_content():
    log_path = "/home/user/status.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_STATUS, (
        f"Log file content is '{content}', expected '{EXPECTED_STATUS}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
