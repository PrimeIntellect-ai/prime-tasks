#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import secrets
import socket
import subprocess
import threading
import time

import pytest

CPP_PATH = "/home/user/generate_audit.cpp"
EXE_PATH = "/home/user/generate_audit"
AUDIT_PATH = "/home/user/audit_trail.txt"
COMPILED_COPY = "/tmp/verifier_generate_audit"
TARGET_PATH = "/login?next=http://attacker.com/steal_cookie"


def run_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return demote


def kill_port_8000():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].upper().endswith(":1F40") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    own_pid = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == own_pid:
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(entry), 9)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.15)


def run_program(path):
    result = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        preexec_fn=run_as_user(),
    )
    assert result.returncode == 0, (
        f"Program {path} failed with exit code {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


def expected_line(url):
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return f"OPEN_REDIRECT_VERIFIED: {url} | SHA256: {digest}"


def assert_audit(url):
    assert os.path.exists(AUDIT_PATH), f"Audit trail file missing: {AUDIT_PATH}"
    assert os.path.isfile(AUDIT_PATH), f"Path is not a file: {AUDIT_PATH}"
    with open(AUDIT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    wanted = expected_line(url)
    assert content == wanted, (
        "Audit trail content does not match expected output.\n"
        f"Expected: {wanted}\nFound:    {content}"
    )


@pytest.fixture(scope="session")
def compiled_source():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", COMPILED_COPY, "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "Submitted C++ source could not be compiled with -lcrypto.\n"
        + result.stderr.decode(errors="replace")
    )
    assert open(COMPILED_COPY, "rb").read(4) == b"\x7fELF"
    return COMPILED_COPY


def test_cpp_source_exists():
    """Test that the C++ source file was created."""
    assert os.path.exists(CPP_PATH), f"C++ source file missing: {CPP_PATH}"
    assert os.path.isfile(CPP_PATH), f"Path is not a file: {CPP_PATH}"


def test_compiled_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.exists(EXE_PATH), f"Compiled executable missing: {EXE_PATH}"
    assert os.path.isfile(EXE_PATH), f"Path is not a file: {EXE_PATH}"
    assert os.access(EXE_PATH, os.X_OK), f"File is not executable: {EXE_PATH}"
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled executable is not an ELF binary"


def test_audit_trail_content(compiled_source):
    """Run the submitted executable against the supplied service and retain the original exact check."""
    kill_port_8000()
    service = subprocess.Popen(
        ["python3", "/home/user/auth_service.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=run_as_user(),
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            assert service.poll() is None, "Authentication service exited before accepting connections"
            try:
                with socket.create_connection(("127.0.0.1", 8000), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail("Authentication service did not start on 127.0.0.1:8000")

        try:
            os.remove(AUDIT_PATH)
        except FileNotFoundError:
            pass
        run_program(EXE_PATH)
        assert_audit("http://attacker.com/steal_cookie")
    finally:
        service.terminate()
        try:
            service.wait(timeout=2)
        except subprocess.TimeoutExpired:
            service.kill()
            service.wait()
        kill_port_8000()


def exercise_dynamic(executable, redirect_url):
    kill_port_8000()
    received = {}
    ready = threading.Event()
    finished = threading.Event()

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", 8000))
                listener.listen(1)
                listener.settimeout(8)
                ready.set()
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(5)
                    data = b""
                    while b"\r\n\r\n" not in data and len(data) < 65536:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    received["request"] = data
                    response = (
                        "HTTP/1.1 302 Found\r\n"
                        f"Location: {redirect_url}\r\n"
                        "Set-Cookie: verifier=test; Path=/\r\n"
                        "Content-Length: 0\r\n"
                        "Connection: close\r\n\r\n"
                    ).encode("ascii")
                    conn.sendall(response)
        except BaseException as exc:
            received["error"] = exc
            ready.set()
        finally:
            finished.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), "Verifier HTTP server did not start"
    assert "error" not in received, f"Verifier HTTP server failed: {received.get('error')}"

    try:
        os.remove(AUDIT_PATH)
    except FileNotFoundError:
        pass
    run_program(executable)
    assert finished.wait(8), "Program did not complete an HTTP exchange"
    assert "error" not in received, f"Verifier HTTP server failed: {received.get('error')}"

    raw = received.get("request", b"")
    header_text = raw.decode("iso-8859-1")
    lines = header_text.split("\r\n")
    assert lines[0] == f"GET {TARGET_PATH} HTTP/1.1", (
        f"Incorrect HTTP request line: {lines[0] if lines else '<missing>'}"
    )
    assert any(
        line.lower().startswith("host:") and line.split(":", 1)[1].strip()
        for line in lines[1:]
    ), "HTTP/1.1 request did not contain a valid Host header"
    assert_audit(redirect_url)


def test_program_parses_location_and_hashes_runtime_value(compiled_source):
    """Exercise both the delivered executable and a fresh build on unpredictable responses."""
    token1 = secrets.token_hex(16)
    url1 = f"http://audit-{token1}.example/redirect?nonce={token1}"
    exercise_dynamic(EXE_PATH, url1)

    token2 = secrets.token_hex(16)
    url2 = f"http://audit-{token2}.example/redirect?nonce={token2}"
    exercise_dynamic(compiled_source, url2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
