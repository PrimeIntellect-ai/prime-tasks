#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import re
import secrets
import signal
import socket
import subprocess
import threading
import time

import pytest

C_SERVER = "/home/user/polyglot-build/c_src/c_server"
GO_PROXY = "/home/user/polyglot-build/go_src/proxy_server"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def kill_port_users(*ports):
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not any(listener_pids(port) for port in ports):
            return
        time.sleep(0.05)
    for port in ports:
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def user_preexec():
    if os.geteuid() != 0:
        return None
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return demote


def request(port, path, attempts=30):
    last_error = None
    for _ in range(attempts):
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
            conn.request("GET", path)
            response = conn.getresponse()
            body = response.read()
            headers = dict(response.getheaders())
            status = response.status
            conn.close()
            return status, headers, body
        except OSError as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Could not query port {port}: {last_error}")


def assert_listener_is_binary(port, binary):
    pids = listener_pids(port)
    assert pids, f"Nothing is listening on required port {port}"
    unexpected = []
    for pid in pids:
        try:
            executable = os.path.realpath(f"/proc/{pid}/exe")
            if not os.path.samefile(executable, binary):
                unexpected.append((pid, executable))
        except (FileNotFoundError, ProcessLookupError):
            unexpected.append((pid, "vanished"))
    assert not unexpected, f"Port {port} is not served by {binary}: {unexpected}"
    return pids


@pytest.fixture(scope="session", autouse=True)
def execute_build_script():
    """Execute the build script as 'user' before running the checks."""
    script_path = "/home/user/build.sh"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist. Did you create it?"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable. Did you run chmod +x?"

    # Ensure pre-existing fake listeners cannot satisfy the live-service checks.
    kill_port_users(8080, 8081)

    try:
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=30,
            cwd="/home/user",
            preexec_fn=user_preexec(),
        )
        assert result.returncode == 0, (
            f"build.sh failed with exit code {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("build.sh execution timed out after 30 seconds. Does it hang or fail to background the servers?")


def test_build_result_log():
    """Verify that build_result.log exists and contains the expected output."""
    log_path = "/home/user/build_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the curl command run and save output?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "POLYGLOT_BACKEND_OK"
    assert expected_content in content, f"Expected '{expected_content}' in {log_path}, but got: '{content}'"
    assert content == expected_content, "build_result.log must contain the raw backend body, not fabricated extra output"


def test_c_server_executable():
    """Verify that the C server was compiled and is executable."""
    assert os.path.isfile(C_SERVER), f"C server binary {C_SERVER} does not exist. Did compilation fail?"
    assert os.access(C_SERVER, os.X_OK), f"C server binary {C_SERVER} is not executable."
    with open(C_SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "c_server is not a compiled ELF binary"


def test_go_proxy_executable():
    """Verify that the Go proxy was compiled and is executable."""
    assert os.path.isfile(GO_PROXY), f"Go proxy binary {GO_PROXY} does not exist. Did compilation fail?"
    assert os.access(GO_PROXY, os.X_OK), f"Go proxy binary {GO_PROXY} is not executable."
    with open(GO_PROXY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy_server is not a compiled ELF binary"
    info = subprocess.run(["go", "version", "-m", GO_PROXY], capture_output=True, text=True)
    assert info.returncode == 0, f"proxy_server is not recognized as a Go binary: {info.stderr}"


def test_makefile_was_repaired():
    broken_path = "/home/user/polyglot-build/c_src/Makefile.broken"
    repaired_path = "/home/user/polyglot-build/c_src/Makefile"
    assert os.path.isfile(repaired_path), "The repaired c_src/Makefile was not created"
    with open(broken_path, "rb") as f:
        broken = f.read()
    expected = re.sub(br"(?m)^ {4}", b"\t", broken)
    with open(repaired_path, "rb") as f:
        repaired = f.read()
    assert repaired == expected, "Makefile is not the required tab-indented repair of Makefile.broken"
    assert b"\tgcc main.c -o c_server" in repaired


def test_proxy_patch_was_applied():
    proxy_source = "/home/user/polyglot-build/go_src/proxy.go"
    with open(proxy_source) as f:
        source = f.read()
    assert 'url.Parse("http://127.0.0.1:8081")' in source, "proxy.go was not patched to use backend port 8081"
    assert 'url.Parse("http://127.0.0.1:9999")' not in source, "The original broken proxy target remains"
    assert 'r.Header.Set("X-Proxy-Version", "1.0")' in source, "The proxy request-header behavior is missing"


def test_live_binaries_and_proxy_behavior():
    backend_pids = assert_listener_is_binary(8081, C_SERVER)
    assert_listener_is_binary(8080, GO_PROXY)

    nonce_path = "/api/status?challenge=" + secrets.token_hex(12)
    direct_status, _, direct_body = request(8081, nonce_path)
    proxy_status, _, proxy_body = request(8080, nonce_path)
    assert direct_status == 200
    assert direct_body == b"POLYGLOT_BACKEND_OK\n"
    assert proxy_status == direct_status
    assert proxy_body == direct_body, "The live proxy did not forward the backend response"

    # Replace the backend briefly with a verifier-controlled challenge endpoint.
    # Its response is unpredictable to build.sh and is returned only when the proxy
    # forwards both the random path and the required request header.
    for pid in backend_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids(8081) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(8081), "The tested C backend did not stop for the proxy challenge"

    token = secrets.token_bytes(24).hex().encode()
    challenge_path = "/verify/" + secrets.token_hex(16)
    observed = {}
    ready = threading.Event()

    def challenge_backend():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 8081))
        server.listen(1)
        server.settimeout(5)
        ready.set()
        try:
            client, _ = server.accept()
            client.settimeout(2)
            data = b""
            while b"\r\n\r\n" not in data and len(data) < 65536:
                part = client.recv(4096)
                if not part:
                    break
                data += part
            text = data.decode("iso-8859-1")
            lines = text.split("\r\n")
            observed["request_line"] = lines[0] if lines else ""
            headers = {}
            for line in lines[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()
            observed["headers"] = headers
            valid = observed["request_line"].startswith(f"GET {challenge_path} ") and headers.get("x-proxy-version") == "1.0"
            body = token if valid else b"invalid proxy request"
            status = b"200 OK" if valid else b"400 Bad Request"
            client.sendall(b"HTTP/1.1 " + status + b"\r\nContent-Type: text/plain\r\nContent-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
            client.close()
        finally:
            server.close()

    thread = threading.Thread(target=challenge_backend, daemon=True)
    thread.start()
    assert ready.wait(2), "Challenge backend failed to start"
    try:
        status, _, body = request(8080, challenge_path, attempts=10)
        assert status == 200
        assert body == token, "Proxy did not return the verifier-controlled backend response"
        assert observed.get("headers", {}).get("x-proxy-version") == "1.0", "Proxy did not add X-Proxy-Version: 1.0"
    finally:
        thread.join(timeout=5)
        # Restore the required backend service after the challenge.
        subprocess.Popen(
            [C_SERVER],
            cwd=os.path.dirname(C_SERVER),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            preexec_fn=user_preexec(),
        )
        request(8081, "/api/status")

    assert_listener_is_binary(8081, C_SERVER)
    assert_listener_is_binary(8080, GO_PROXY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
