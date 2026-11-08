#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import secrets
import signal
import socket
import subprocess
import time

SERVICE_DIR = "/home/user/auth_service"
SOURCE = os.path.join(SERVICE_DIR, "auth.c")
BINARY = os.path.join(SERVICE_DIR, "auth_server")
OLD_KEY = os.path.join(SERVICE_DIR, "old_secret.key")
NEW_KEY = os.path.join(SERVICE_DIR, "new_secret.key")
PORT = 8080


def test_verification_log_exists_and_correct():
    path = "/home/user/auth_service/verification.log"
    assert os.path.isfile(path), f"Log file {path} is missing. The agent did not create the verification log."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "OLD_TOKEN_VALID: 302 | /home",
        "NEW_TOKEN_VALID: 302 | /settings",
        "OPEN_REDIRECT_BLOCKED: 302 | /dashboard"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {path}. The verification log is incomplete or incorrectly formatted."


def test_auth_c_modifications():
    path = "/home/user/auth_service/auth.c"
    assert os.path.isfile(path), f"Source file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "new_secret.key" in content, f"The file {path} does not reference 'new_secret.key'. Credential rotation logic is missing."
    has_http_check = "http://" in content or "https://" in content or "http" in content
    assert has_http_check, f"The file {path} does not appear to check for 'http' or 'https' in the redirect URL. Open redirect vulnerability may not be fixed."
    assert "/dashboard" in content, f"The file {path} does not contain the fallback redirect path '/dashboard'."


def test_auth_server_compiled():
    path = "/home/user/auth_service/auth_server"
    assert os.path.isfile(path), f"Compiled binary {path} is missing. The agent did not compile the modified C code."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        try:
                            port = int(fields[1].rsplit(":", 1)[1], 16)
                        except ValueError:
                            continue
                        if port == PORT:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def processes_holding(inodes):
    pids = set()
    if not inodes:
        return pids
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            target = os.readlink(fd)
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pid = int(fd.split("/")[2])
                if pid > 1 and pid != os.getpid():
                    pids.add(pid)
        except (FileNotFoundError, PermissionError, OSError, ValueError):
            pass
    return pids


def clear_port():
    pids = processes_holding(listener_inodes())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.15)
    for pid in pids | processes_holding(listener_inodes()):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Could not clear port 8080 before testing the submitted server."


def wait_for_server(proc):
    deadline = time.time() + 4
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                return
        except OSError:
            if proc.poll() is not None:
                time.sleep(0.05)
            else:
                time.sleep(0.05)
    raise AssertionError("The executable did not start an HTTP server on port 8080.")


def request(path, token):
    auth = ""
    if token is not None:
        encoded = base64.b64encode(token.encode()).decode()
        auth = f"Authorization: Bearer {encoded}\r\n"
    raw = (
        f"GET /login?redirect={path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1\r\n"
        f"{auth}"
        f"Connection: close\r\n\r\n"
    ).encode()

    with socket.create_connection(("127.0.0.1", PORT), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(raw)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    response = b"".join(chunks).decode("iso-8859-1")
    lines = response.split("\r\n")
    assert lines and lines[0].startswith("HTTP/"), f"Malformed HTTP response: {response!r}"
    status = int(lines[0].split()[1])
    location = None
    for line in lines[1:]:
        if line.lower().startswith("location:"):
            location = line.split(":", 1)[1].strip()
            break
    return status, location


def exercise(program, old_secret, new_secret, relative_path, external_https, external_http):
    clear_port()
    proc = subprocess.Popen(
        [program], cwd=SERVICE_DIR,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_server(proc)
        assert request("/home", old_secret) == (302, "/home")
        assert request(relative_path, new_secret) == (302, relative_path)
        assert request(external_https, new_secret) == (302, "/dashboard")
        assert request(external_http, new_secret) == (302, "/dashboard")
        status, location = request("/private", "invalid-" + secrets.token_hex(12))
        assert status == 401, "A token matching neither secret must be rejected."
        assert location is None, "An unauthorized response must not contain a Location header."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)
        clear_port()


def test_live_authentication_and_redirect_behavior():
    with open(OLD_KEY, "rb") as f:
        original_old = f.read()
    with open(NEW_KEY, "rb") as f:
        original_new = f.read()

    old_secret = "old_" + secrets.token_hex(12)
    new_secret = "new_" + secrets.token_hex(12)
    relative_path = "/profile-" + secrets.token_hex(4)
    external_https = "https://" + secrets.token_hex(6) + ".example/login"
    external_http = "http://" + secrets.token_hex(6) + ".example/login"
    rebuilt = "/tmp/auth_server_rebuilt"

    try:
        with open(OLD_KEY, "w") as f:
            f.write(old_secret + "\n")
        with open(NEW_KEY, "w") as f:
            f.write(new_secret + "\n")

        result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"Modified auth.c does not compile:\n{result.stderr}"

        exercise(BINARY, old_secret, new_secret, relative_path, external_https, external_http)
        exercise(rebuilt, old_secret, new_secret, relative_path, external_https, external_http)
    finally:
        clear_port()
        with open(OLD_KEY, "wb") as f:
            f.write(original_old)
        with open(NEW_KEY, "wb") as f:
            f.write(original_new)
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
