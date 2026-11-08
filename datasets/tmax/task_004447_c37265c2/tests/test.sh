#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_final_state.py
import hashlib
import os
import random
import re
import secrets
import signal
import socket
import ssl
import subprocess
import time

HOME = "/home/user"
SOURCE = HOME + "/honeypot.c"
BINARY = HOME + "/honeypot"
CERT = HOME + "/certs/server.crt"
KEY = HOME + "/certs/server.key"
JAIL = HOME + "/jail"
PORT = 8443


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == PORT:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.append(int(name))
                    break
        except OSError:
            continue
    return sorted(set(found))


def wait_for_listener(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids()
        if pids:
            return pids[0]
        time.sleep(0.1)
    raise AssertionError("No process found listening on port 8443")


def assert_process_state(pid, expected_executable):
    proc_path = f"/proc/{pid}"
    assert os.path.isdir(proc_path), f"Process directory {proc_path} does not exist"
    uid = os.stat(proc_path).st_uid
    assert uid == 65534, f"Process {pid} is running as UID {uid}, expected 65534 (nobody)"
    root_link = os.readlink(f"{proc_path}/root")
    assert root_link == JAIL, f"Process {pid} is chrooted to {root_link}, expected {JAIL}"
    expected_stat = os.stat(expected_executable)
    running_stat = os.stat(f"{proc_path}/exe")
    assert (running_stat.st_dev, running_stat.st_ino) == (expected_stat.st_dev, expected_stat.st_ino), \
        f"Port 8443 is not served by {expected_executable}"


def stop_listeners():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), "Could not stop the existing port 8443 listener"


def tls_get(path, cookie_header, expected_cert_der):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="honeypot.local") as conn:
            served_der = conn.getpeercert(binary_form=True)
            assert hashlib.sha256(served_der).digest() == hashlib.sha256(expected_cert_der).digest(), \
                "The listener is not serving /home/user/certs/server.crt"
            headers = [
                f"GET {path} HTTP/1.1",
                "Host: honeypot.local",
                "Connection: close",
                "User-Agent: verifier-" + secrets.token_hex(6),
            ]
            if cookie_header is not None:
                headers.append("Cookie: " + cookie_header)
            conn.sendall(("\r\n".join(headers) + "\r\n\r\n").encode("ascii"))
            chunks = []
            while True:
                data = conn.recv(65536)
                if not data:
                    break
                chunks.append(data)
    response = b"".join(chunks)
    head, separator, body = response.partition(b"\r\n\r\n")
    assert separator, f"Listener returned a malformed HTTP response: {response[:200]!r}"
    first_line = head.split(b"\r\n", 1)[0]
    match = re.match(br"HTTP/\d(?:\.\d)?\s+(\d{3})(?:\s|$)", first_line)
    assert match, f"Listener returned a malformed HTTP status line: {first_line!r}"
    return int(match.group(1)), body


def main():
    password_path = HOME + "/cracked_password.txt"
    assert os.path.isfile(password_path), f"File {password_path} does not exist"
    with open(password_path) as f:
        password = f.read().strip()
    assert password == "Secure_7382", f"Expected 'Secure_7382', but found {password!r}"

    assert os.path.isfile(CERT), f"Certificate file {CERT} is missing"
    assert os.path.isfile(KEY), f"Private key file {KEY} is missing"
    result = subprocess.run(
        ["openssl", "x509", "-noout", "-subject", "-in", CERT],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Failed to read certificate: {result.stderr}"
    assert "CN = honeypot.local" in result.stdout or "CN=honeypot.local" in result.stdout, \
        f"Certificate does not have Common Name honeypot.local: {result.stdout.strip()}"
    with open(CERT) as f:
        expected_cert_der = ssl.PEM_cert_to_DER_cert(f.read())

    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing"
    assert os.path.getsize(SOURCE) > 0, f"C source file {SOURCE} is empty"
    assert os.path.isfile(BINARY), f"Compiled honeypot {BINARY} is missing"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable"

    original_pid = wait_for_listener()
    assert_process_state(original_pid, BINARY)

    rebuilt = "/tmp/honeypot.rebuilt"
    build = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", rebuilt, "-lssl", "-lcrypto"],
        capture_output=True, text=True
    )
    assert build.returncode == 0, \
        f"honeypot.c did not compile as C with OpenSSL: {build.stdout}\n{build.stderr}"

    stop_listeners()
    os.chmod(rebuilt, 0o755)
    os.replace(rebuilt, BINARY)
    subprocess.Popen(
        [BINARY], cwd=HOME, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    rebuilt_pid = wait_for_listener()
    assert_process_state(rebuilt_pid, BINARY)

    cases = []
    for _ in range(6):
        cases.append(("valid", f"AuthToken={password}", 200))
        wrong = "Secure_" + str(secrets.randbelow(10000)).zfill(4)
        if wrong == password:
            wrong = "Secure_0000"
        cases.append(("invalid", f"AuthToken={wrong}", 403))
        cases.append(("missing", None, 403))
    random.SystemRandom().shuffle(cases)

    for kind, cookie, expected_status in cases:
        path = "/probe-" + secrets.token_urlsafe(12)
        status, body = tls_get(path, cookie, expected_cert_der)
        assert status == expected_status, \
            f"{kind} randomized request returned HTTP {status}, expected {expected_status}"
        if kind == "valid":
            assert b"ACCESS GRANTED" in body, \
                f"Valid request body did not contain ACCESS GRANTED: {body!r}"

    final_pid = wait_for_listener()
    assert_process_state(final_pid, BINARY)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
