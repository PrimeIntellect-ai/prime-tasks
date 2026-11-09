#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import time

HOST = "127.0.0.1"
PORT = 8080
LOG_PATH = "/home/user/access.log"
SERVER_PATH = "/home/user/server"
SOURCE_PATH = "/home/user/server.c"
VERIFIER_SERVER = "/tmp/verifier-built-server"


def send_request(path):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((HOST, PORT))
        req = f"GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n"
        s.sendall(req.encode())
        chunks = []
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode(errors="replace")
    finally:
        s.close()


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def wait_for_port(open_expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.2)
        try:
            is_open = s.connect_ex((HOST, PORT)) == 0
        finally:
            s.close()
        if is_open == open_expected:
            return
        time.sleep(0.05)
    raise AssertionError(f"Port {PORT} did not become {'open' if open_expected else 'closed'}")


def clear_log():
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass


def assert_server_artifact_and_running():
    # Preserve the original artifact and listener assertions.
    assert os.path.isfile(SERVER_PATH), "Server executable /home/user/server not found. Did you compile it?"
    assert os.access(SERVER_PATH, os.X_OK), "Server executable is not executable."

    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not a compiled executable."

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    result = s.connect_ex((HOST, PORT))
    s.close()
    assert result == 0, "Server is not listening on port 8080. Did you run it in the background?"

    expected = os.stat(SERVER_PATH)
    running_expected_binary = False
    for pid in listener_pids():
        try:
            actual = os.stat(f"/proc/{pid}/exe")
            if (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino):
                running_expected_binary = True
                break
        except OSError:
            pass
    assert running_expected_binary, "The process listening on port 8080 is not /home/user/server."


def run_behavioral_suite():
    clear_log()

    # Preserve all fixed behavioral assertions from the original verifier.
    resp = send_request("/login?redirect=http://evil.com")
    assert "Location: /dashboard\r\n" in resp, "Invalid redirect did not default to /dashboard."

    resp = send_request("/login?redirect=/profile/settings")
    assert "Location: /profile/settings\r\n" in resp, "Valid redirect to /profile was altered or blocked."

    resp = send_request("/index.html")
    assert "Content-Security-Policy: default-src 'self'" in resp, "CSP header missing or incorrect in 200 OK response."

    send_request("/api?user=1&token=SUPERSECRET&action=view")
    time.sleep(0.1)
    assert os.path.isfile(LOG_PATH), "access.log not found. The server did not create the log file."
    with open(LOG_PATH) as f:
        log_contents = f.read()
    assert "token=REDACTED&action=view" in log_contents, "Token was not correctly redacted in the log."
    assert "SUPERSECRET" not in log_contents, "Token secret leaked in the log file."

    # Exercise both allowed prefixes and varied invalid redirect values.
    marker = secrets.token_hex(8)
    allowed = [
        f"/dashboard/{marker}",
        f"/profile?tab={marker}",
    ]
    for target in allowed:
        resp = send_request("/login?redirect=" + target)
        assert "HTTP/1.1 302 Found" in resp
        assert f"Location: {target}\r\n" in resp, f"Allowed redirect target {target!r} was altered or blocked."

    invalid = [
        f"http://{marker}.invalid/path",
        f"//{marker}.invalid/path",
        f"/{marker}/dashboard",
        f"/Dashboard/{marker}",
    ]
    for target in invalid:
        resp = send_request("/login?redirect=" + target)
        assert "HTTP/1.1 302 Found" in resp
        assert "Location: /dashboard\r\n" in resp, f"Invalid redirect target {target!r} was permitted."
        assert f"Location: {target}\r\n" not in resp

    # Check the CSP on multiple dynamically selected ordinary paths.
    for path in (f"/page-{marker}.html", f"/assets/{marker}"):
        resp = send_request(path)
        assert "HTTP/1.1 200 OK" in resp
        assert "Content-Security-Policy: default-src 'self';\r\n" in resp, f"CSP header missing or incorrect for {path}."

    # Vary token values and positions and derive the exact expected log lines.
    cases = []
    for template in (
        "/api?token={token}",
        "/api?token={token}&action=list",
        "/api?user=2&token={token}&action=edit",
        "/search?q=item&mode=full&token={token}",
    ):
        token = "tok_" + secrets.token_hex(12)
        path = template.format(token=token)
        expected = path.replace(token, "REDACTED", 1)
        cases.append((path, expected, token))
        send_request(path)

    time.sleep(0.1)
    with open(LOG_PATH) as f:
        log_contents = f.read()
    for path, expected, token in cases:
        assert f"REQ: GET {expected}\n" in log_contents, f"Incorrect redaction for request path {path!r}."
        assert token not in log_contents, f"Token value {token!r} leaked in access.log."


def stop_port_listener():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    wait_for_port(False)


def main():
    assert os.path.isfile(SOURCE_PATH), "/home/user/server.c not found."
    assert_server_artifact_and_running()
    run_behavioral_suite()

    # Compile the submitted source independently, then execute that build so a
    # hardcoded substitute listener cannot stand in for modifications to server.c.
    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", VERIFIER_SERVER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, "Submitted server.c does not compile:\n" + result.stderr

    stop_port_listener()
    clear_log()
    proc = subprocess.Popen([VERIFIER_SERVER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_port(True)
        run_behavioral_suite()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
