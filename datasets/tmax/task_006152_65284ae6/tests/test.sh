#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import ssl
import stat
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest

APP_DIR = "/home/user/app"
SOURCE = os.path.join(APP_DIR, "upload_server.go")
SUBMITTED_BINARY = os.path.join(APP_DIR, "upload_server")
UPLOAD_DIR = os.path.join(APP_DIR, "uploads")
RUNNING_SERVER = None


def test_ssh_keys_cleaned():
    path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "legitimate@admin" in content, "Legitimate SSH key was removed."
    assert "hacker@evil" not in content, "Rogue SSH key 'hacker@evil' is still present."


def test_audit_report_created():
    path = "/home/user/audit_report.txt"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "Vulnerability fixed and mTLS enabled", "Audit report content is incorrect."


def test_certs_generated():
    cert_dir = "/home/user/certs"
    assert os.path.isdir(cert_dir), f"Directory {cert_dir} does not exist"

    expected_files = ["ca.crt", "ca.key", "server.crt", "server.key", "client.crt", "client.key"]
    for name in expected_files:
        file_path = os.path.join(cert_dir, name)
        assert os.path.isfile(file_path), f"Certificate file {file_path} is missing."


def listening_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A" and fields[1].rsplit(":", 1)[-1].upper() == wanted:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def stop_port_8443():
    inodes = listening_inodes(8443)
    if not inodes:
        return

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in victims:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2
        while time.time() < deadline and listening_inodes(8443):
            time.sleep(0.05)
        if not listening_inodes(8443):
            return

    assert not listening_inodes(8443), "Could not stop the pre-existing listener on port 8443."


def wait_for_listener(proc):
    deadline = time.time() + 8
    while time.time() < deadline:
        assert proc.poll() is None, f"Server process exited early with status {proc.returncode}."
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            if s.connect_ex(("127.0.0.1", 8443)) == 0:
                return
        time.sleep(0.1)
    pytest.fail("Server did not begin listening on port 8443.")


def launch_server(path):
    proc = subprocess.Popen(
        [path],
        cwd=APP_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_listener(proc)
    return proc


def request_post(filename, body, context):
    query = urllib.parse.urlencode({"filename": filename})
    req = urllib.request.Request(
        f"https://localhost:8443/upload?{query}",
        data=body,
        method="POST",
    )
    return urllib.request.urlopen(req, context=context, timeout=3)


def assert_client_certificate_required(ca_crt):
    context_no_cert = ssl.create_default_context(cafile=ca_crt)
    rejected = False
    sock = None
    tls_sock = None
    try:
        sock = socket.create_connection(("127.0.0.1", 8443), timeout=3)
        tls_sock = context_no_cert.wrap_socket(sock, server_hostname="localhost")
        sock = None
        tls_sock.settimeout(3)
        tls_sock.sendall(
            b"GET /upload?filename=test.txt HTTP/1.1\r\n"
            b"Host: localhost\r\nConnection: close\r\n\r\n"
        )
        data = tls_sock.recv(4096)
        rejected = data == b""
        assert not data, (
            "Server returned an HTTP response without a client certificate; "
            "the TLS layer is not requiring mTLS."
        )
    except (ssl.SSLError, ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
        rejected = True
    finally:
        if tls_sock is not None:
            tls_sock.close()
        elif sock is not None:
            sock.close()

    assert rejected, "Server accepted a TLS request without a client certificate."


def exercise_server():
    ca_crt = "/home/user/certs/ca.crt"
    client_crt = "/home/user/certs/client.crt"
    client_key = "/home/user/certs/client.key"
    assert os.path.isfile(ca_crt) and os.path.isfile(client_crt) and os.path.isfile(client_key), \
        "Cannot test mTLS because client/CA certificates are missing."

    context_mtls = ssl.create_default_context(cafile=ca_crt)
    context_mtls.load_cert_chain(certfile=client_crt, keyfile=client_key)

    # Confirm that the generated CA validates the server and its client certificate is accepted.
    probe_name = f"probe-{uuid.uuid4().hex}.txt"
    with request_post(probe_name, b"probe", context_mtls) as resp:
        assert resp.status == 200, f"Expected HTTP 200 for valid upload, got {resp.status}"

    assert_client_certificate_required(ca_crt)

    # Preserve the original fixed traversal assertion.
    original_escape = "/home/user/app/evil.txt"
    try:
        os.remove(original_escape)
    except FileNotFoundError:
        pass
    try:
        request_post("../evil.txt", b"malicious content", context_mtls)
        pytest.fail("Path traversal attempt succeeded, expected HTTP 400.")
    except urllib.error.HTTPError as e:
        assert e.code == 400, f"Expected HTTP 400 for path traversal, got {e.code}"
    assert not os.path.exists(original_escape), "Traversal upload wrote outside the uploads directory."

    # Exercise unpredictable escaping paths so a single filename cannot be special-cased.
    token = uuid.uuid4().hex
    traversal_cases = [
        (f"../escape-{token}-a.txt", f"/home/user/app/escape-{token}-a.txt"),
        (f"nested/../../escape-{token}-b.txt", f"/home/user/app/escape-{token}-b.txt"),
        (f"./../../escape-{token}-c.txt", f"/home/user/escape-{token}-c.txt"),
    ]
    for filename, escaped_path in traversal_cases:
        try:
            os.remove(escaped_path)
        except FileNotFoundError:
            pass
        try:
            request_post(filename, b"dynamic malicious content", context_mtls)
            pytest.fail(f"Path traversal attempt {filename!r} succeeded, expected HTTP 400.")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Expected HTTP 400 for {filename!r}, got {e.code}"
        assert not os.path.exists(escaped_path), f"Traversal wrote outside uploads: {escaped_path}"

    # Preserve the original valid-upload assertion.
    with request_post("good.txt", b"safe content", context_mtls) as resp:
        assert resp.status == 200, f"Expected HTTP 200 for valid upload, got {resp.status}"

    upload_path = "/home/user/app/uploads/good.txt"
    assert os.path.isfile(upload_path), "Valid uploaded file was not saved to the correct directory."
    with open(upload_path, "rb") as f:
        assert f.read() == b"safe content", "Uploaded file content does not match."


def test_source_compiles_and_both_artifacts_are_secure():
    global RUNNING_SERVER

    assert os.path.isfile(SOURCE), f"Go source {SOURCE} is missing."
    assert os.path.isfile(SUBMITTED_BINARY), f"Compiled server {SUBMITTED_BINARY} is missing."
    mode = os.stat(SUBMITTED_BINARY).st_mode
    assert stat.S_ISREG(mode), "Compiled server is not a regular file."
    assert mode & 0o111, "Compiled server is not executable."

    rebuilt = f"/tmp/upload_server_from_source_{uuid.uuid4().hex}"
    build = subprocess.run(
        ["go", "build", "-o", rebuilt, SOURCE],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Modified Go source does not compile:\n{build.stderr}"

    stop_port_8443()
    source_proc = launch_server(rebuilt)
    try:
        exercise_server()
    finally:
        if source_proc.poll() is None:
            source_proc.terminate()
            try:
                source_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                source_proc.kill()
                source_proc.wait(timeout=3)
        stop_port_8443()

    # Execute and test the required submitted binary, then leave it running.
    RUNNING_SERVER = launch_server(SUBMITTED_BINARY)
    exercise_server()
    assert RUNNING_SERVER.poll() is None, "Compiled server stopped running during verification."


def test_server_listening_port_8443():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(("127.0.0.1", 8443))
        assert result == 0, "Server is not listening on port 8443."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
