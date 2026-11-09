#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import queue
import secrets
import signal
import socket
import string
import subprocess
import tempfile
import threading
import time

import pytest

SANITIZER = "/home/user/sanitizer"


def run_sanitizer(path, payload):
    return subprocess.run([path], input=payload, capture_output=True, timeout=5)


def assert_sanitizer_result(path, payload, rejected):
    proc = run_sanitizer(path, payload)
    expected_code = 1 if rejected else 0
    expected_text = b"REJECTED" if rejected else b"ACCEPTED"
    assert proc.returncode == expected_code, (
        f"sanitizer returned {proc.returncode}, expected {expected_code}, "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert proc.stdout.strip() == expected_text, (
        f"sanitizer stdout was {proc.stdout!r}, expected {expected_text!r}"
    )


def test_deliverables_exist():
    assert os.path.isfile("/home/user/sanitizer.c"), "/home/user/sanitizer.c is missing."
    assert os.path.isfile(SANITIZER), "/home/user/sanitizer binary is missing."
    assert os.access(SANITIZER, os.X_OK), "/home/user/sanitizer is not executable."
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/sanitizer is not a compiled executable."

    assert os.path.isfile("/home/user/pipeline.sh"), "/home/user/pipeline.sh is missing."
    assert os.access("/home/user/pipeline.sh", os.X_OK), "/home/user/pipeline.sh is not executable."

    assert os.path.isfile("/home/user/proxy.sh"), "/home/user/proxy.sh is missing."
    assert os.access("/home/user/proxy.sh", os.X_OK), "/home/user/proxy.sh is not executable."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    bypassed_evil = []
    modified_clean = []

    for filename in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                proc = run_sanitizer(SANITIZER, f.read())
            if proc.returncode != 1:
                bypassed_evil.append(filename)
            assert proc.stdout.strip() == b"REJECTED", f"Wrong stdout for evil file {filename}: {proc.stdout!r}"

    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                proc = run_sanitizer(SANITIZER, f.read())
            if proc.returncode != 0:
                modified_clean.append(filename)
            assert proc.stdout.strip() == b"ACCEPTED", f"Wrong stdout for clean file {filename}: {proc.stdout!r}"

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} evil files bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} clean files rejected: {', '.join(modified_clean)}")
    assert not errors, " | ".join(errors)


def randomized_cases():
    alphabet = string.ascii_letters + string.digits
    nonce = "".join(secrets.choice(alphabet) for _ in range(48)).encode()
    clean = [
        b"",
        nonce,
        b"prefix UNION  SELECT suffix " + nonce,
        b"prefix OR 1 =1 suffix " + nonce,
        b"prefix <script > suffix " + nonce,
        b"prefix DROP\nTABLE suffix " + nonce,
        b"ordinary HTTP text\r\nX-Nonce: " + nonce + b"\r\n\r\nbody",
    ]
    patterns = [b"UNION SELECT", b"OR 1=1", b"<script>", b"DROP TABLE"]
    evil = []
    for pattern in patterns:
        mixed = bytes(
            (chr(c).lower() if secrets.randbelow(2) else chr(c).upper()).encode()[0]
            if 65 <= c <= 90 or 97 <= c <= 122 else c
            for c in pattern
        )
        evil.append(nonce[:17] + mixed + nonce[17:])
    evil.append((b"A" * 180000) + b"dRoP tAbLe" + nonce)
    evil.append(nonce + b"<ScRiPt>" + b" and UNION SELECT")
    return clean, evil


def test_dynamic_sanitizer_behavior_and_source():
    clean, evil = randomized_cases()
    for payload in clean:
        assert_sanitizer_result(SANITIZER, payload, False)
    for payload in evil:
        assert_sanitizer_result(SANITIZER, payload, True)

    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt-sanitizer-")
    os.close(fd)
    try:
        proc = subprocess.run(
            ["gcc", "/home/user/sanitizer.c", "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert proc.returncode == 0, f"sanitizer.c does not compile: {proc.stdout} {proc.stderr}"
        for payload in clean:
            assert_sanitizer_result(rebuilt, payload, False)
        for payload in evil:
            assert_sanitizer_result(rebuilt, payload, True)
    finally:
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass


def test_pipeline_script():
    proc = subprocess.run(["/home/user/pipeline.sh"], capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0, (
        f"pipeline.sh failed with exit code {proc.returncode}. "
        f"Output: {proc.stdout} {proc.stderr}"
    )
    assert "PIPELINE SUCCESS" in proc.stdout, "pipeline.sh did not print 'PIPELINE SUCCESS'."

    backup = SANITIZER + ".verifier-backup"
    os.replace(SANITIZER, backup)
    try:
        with open(SANITIZER, "w") as f:
            f.write("#!/bin/sh\necho ACCEPTED\nexit 0\n")
        os.chmod(SANITIZER, 0o755)
        proc = subprocess.run(["/home/user/pipeline.sh"], capture_output=True, text=True, timeout=30)
        assert proc.returncode != 0, "pipeline.sh succeeded even when every evil corpus item was accepted."
    finally:
        try:
            os.unlink(SANITIZER)
        except FileNotFoundError:
            pass
        os.replace(backup, SANITIZER)


def stop_original_services():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read()
            if b"/app/backend.py" in cmdline or b"/app/audit.py" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.4)


def expected_backend_response(data):
    body = b"backend-capture:" + hashlib.sha256(data).hexdigest().encode()
    return (
        b"HTTP/1.1 200 OK\r\n"
        + b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        + b"Connection: close\r\n\r\n"
        + body
    )


def read_http_message(conn):
    data = b""
    target = None
    conn.settimeout(1.0)
    while True:
        try:
            chunk = conn.recv(65536)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
        if target is None and b"\r\n\r\n" in data:
            head, body = data.split(b"\r\n\r\n", 1)
            length = 0
            for line in head.split(b"\r\n")[1:]:
                if line.lower().startswith(b"content-length:"):
                    length = int(line.split(b":", 1)[1].strip())
            target = len(head) + 4 + length
        if target is not None and len(data) >= target:
            break
    return data


class CaptureServer(threading.Thread):
    def __init__(self, port, respond):
        super().__init__(daemon=True)
        self.port = port
        self.respond = respond
        self.messages = queue.Queue()
        self.ready = threading.Event()
        self.error = None
        self.sock = None

    def run(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock = s
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            deadline = time.time() + 4
            while True:
                try:
                    s.bind(("127.0.0.1", self.port))
                    break
                except OSError:
                    if time.time() >= deadline:
                        raise
                    time.sleep(0.1)
            s.listen(20)
            s.settimeout(0.2)
            self.ready.set()
            while True:
                try:
                    conn, _ = s.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                with conn:
                    data = read_http_message(conn)
                    self.messages.put(data)
                    if self.respond:
                        conn.sendall(expected_backend_response(data))
        except Exception as exc:
            self.error = exc
            self.ready.set()

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass


def send_tcp_request(port, payload):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3.0)
        s.connect(("127.0.0.1", port))
        s.sendall(payload)
        s.shutdown(socket.SHUT_WR)
        response = b""
        while True:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            response += chunk
        s.close()
        return response
    except Exception:
        return b""


def make_request(path, body):
    return (
        b"POST /" + path + b" HTTP/1.1\r\n"
        b"Host: localhost\r\n"
        b"Content-Type: application/octet-stream\r\n"
        b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        b"Connection: close\r\n\r\n" + body
    )


def drain(q):
    result = []
    while True:
        try:
            result.append(q.get_nowait())
        except queue.Empty:
            return result


def test_end_to_end_routing_forwarding_and_audit():
    stop_original_services()
    backend = CaptureServer(8081, True)
    audit = CaptureServer(8082, False)
    backend.start()
    audit.start()
    assert backend.ready.wait(5) and backend.error is None, f"Could not start backend capture: {backend.error}"
    assert audit.ready.wait(5) and audit.error is None, f"Could not start audit capture: {audit.error}"

    try:
        nonce = secrets.token_hex(24).encode()
        original_clean = b"GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 16\r\n\r\n{\"user\": \"test\"}"
        original_evil_body = b"{\"data\": \"admin' OR 1=1 --\"}"
        original_evil = make_request(b"original-evil", original_evil_body)

        clean_requests = [
            original_clean,
            make_request(b"clean-" + secrets.token_hex(6).encode(), b"safe:" + nonce),
            make_request(b"another-" + secrets.token_hex(6).encode(), b"UNION  SELECT is only a near miss " + nonce),
        ]
        evil_patterns = [b"uNiOn SeLeCt", b"Or 1=1", b"<ScRiPt>", b"dRoP TaBlE"]
        evil_requests = [original_evil]
        for i, pattern in enumerate(evil_patterns):
            evil_requests.append(make_request(
                b"evil-" + str(i).encode() + b"-" + secrets.token_hex(5).encode(),
                nonce[:11] + pattern + nonce[11:],
            ))

        for payload in clean_requests:
            response = send_tcp_request(8080, payload)
            assert response, "No response received from proxy on port 8080 for clean request."
            assert b"403 Forbidden" not in response, "Clean request was incorrectly blocked."
            assert response == expected_backend_response(payload), (
                "Proxy did not return the exact response produced by the backend for the exact request."
            )

        for payload in evil_requests:
            response = send_tcp_request(8080, payload)
            assert response, "No response received from proxy on port 8080 for evil request."
            assert b"403 Forbidden" in response, "Evil request was not blocked with 403 Forbidden."
            assert response == b"HTTP/1.1 403 Forbidden\r\n\r\n", "Proxy returned an incorrect rejection response."

        deadline = time.time() + 4
        while time.time() < deadline:
            if backend.messages.qsize() >= len(clean_requests) and audit.messages.qsize() >= len(evil_requests):
                break
            time.sleep(0.05)

        backend_messages = drain(backend.messages)
        audit_messages = drain(audit.messages)
        assert backend_messages == clean_requests, (
            "Backend did not receive each clean request exactly, or received a rejected request. "
            f"Captured {len(backend_messages)} messages."
        )
        assert audit_messages == evil_requests, (
            "Audit logger did not receive each rejected request exactly, or received a clean request. "
            f"Captured {len(audit_messages)} messages."
        )
    finally:
        backend.close()
        audit.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
