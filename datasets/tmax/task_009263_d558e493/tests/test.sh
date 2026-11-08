#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.server
import json
import os
import signal
import socket
import subprocess
import threading
import time
import uuid
import urllib.error
import urllib.request

import pytest

INFRA = "/home/user/infra"
CONFIG = os.path.join(INFRA, "config.json")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
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
        except OSError:
            pass
    return pids


def kill_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and listener_pids(port):
        time.sleep(0.05)


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def run_monitor():
    return subprocess.run(
        ["bash", os.path.join(INFRA, "run_monitor.sh")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def test_01_scripts_exist():
    assert os.path.isfile("/home/user/infra/proxy.py"), "/home/user/infra/proxy.py is missing"
    assert os.path.isfile("/home/user/infra/monitor.py"), "/home/user/infra/monitor.py is missing"
    assert os.path.isfile("/home/user/provision.sh"), "/home/user/provision.sh is missing"


def test_02_provisioning_and_health_check():
    kill_port(9090)
    kill_port(8080)
    log_path = os.path.join(INFRA, "logs/health.log")
    for path in (log_path, "/logs/health.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.monotonic()
    try:
        result = subprocess.run(
            ["bash", "/home/user/provision.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("provision.sh did not exit after starting its background services")
    elapsed = time.monotonic() - started

    assert result.returncode == 0, f"provision.sh failed with exit code {result.returncode}\n{result.stderr}"
    assert elapsed >= 1.7, "provision.sh did not perform the required two-second startup wait"

    time.sleep(0.4)
    api_pids = listener_pids(8080)
    proxy_pids = listener_pids(9090)
    assert api_pids, "provision.sh did not leave a service listening on port 8080"
    assert proxy_pids, "provision.sh did not leave a service listening on port 9090"
    assert any("/home/user/infra/api.py" in cmdline(pid) for pid in api_pids), \
        "the port 8080 listener was not started from api.py"
    assert any("/home/user/infra/proxy.py" in cmdline(pid) for pid in proxy_pids), \
        "the port 9090 listener was not started from proxy.py"

    url = "http://127.0.0.1:9090/health"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            status = response.getcode()
            body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to proxy at {url}: {exc}")
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert body == "OK", f"Expected body 'OK', got '{body}'"

    assert os.path.isfile(log_path), f"Log file {log_path} was not created. monitor.py likely failed to resolve its path."
    with open(log_path) as f:
        lines = f.read().splitlines()
    assert lines == ["STATUS: OK"], f"Expected exactly one STATUS: OK line, got {lines!r}"


class RecordingHandler(http.server.BaseHTTPRequestHandler):
    status = 200
    requests = []

    def do_GET(self):
        type(self).requests.append(self.path)
        self.send_response(type(self).status)
        self.end_headers()
        self.wfile.write(os.urandom(9))

    def log_message(self, *args):
        pass


def start_http(status):
    handler = type(f"Handler{uuid.uuid4().hex}", (RecordingHandler,), {"status": status, "requests": []})
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, handler


def test_03_monitor_reads_config_resolves_path_and_logs_exact_results():
    with open(CONFIG, "rb") as f:
        original_config = f.read()

    name = f"monitor-{uuid.uuid4().hex}.log"
    relative_log = f"logs/{name}"
    correct_log = os.path.join(INFRA, relative_log)
    wrong_log = os.path.join("/", relative_log)
    os.makedirs(os.path.dirname(correct_log), exist_ok=True)
    os.makedirs(os.path.dirname(wrong_log), exist_ok=True)
    for path in (correct_log, wrong_log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    with open(correct_log, "w") as f:
        f.write("SENTINEL\n")

    try:
        ok_server, ok_handler = start_http(200)
        ok_port = ok_server.server_address[1]
        with open(CONFIG, "w") as f:
            json.dump({"target_port": ok_port, "log_path": relative_log}, f)
        result = run_monitor()
        ok_server.shutdown()
        ok_server.server_close()
        assert result.returncode == 0, f"monitor failed on HTTP 200: {result.stderr}"
        assert ok_handler.requests == ["/health"], f"monitor requested {ok_handler.requests!r}, not exactly /health"
        with open(correct_log) as f:
            assert f.read().splitlines() == ["SENTINEL", "STATUS: OK"]
        assert not os.path.exists(wrong_log), "monitor resolved the relative log path against / instead of its own directory"

        fail_server, fail_handler = start_http(503)
        fail_port = fail_server.server_address[1]
        with open(CONFIG, "w") as f:
            json.dump({"target_port": fail_port, "log_path": relative_log}, f)
        run_monitor()
        fail_server.shutdown()
        fail_server.server_close()
        assert fail_handler.requests == ["/health"], "monitor did not make the configured health request for a failing HTTP response"
        with open(correct_log) as f:
            assert f.read().splitlines() == ["SENTINEL", "STATUS: OK", "STATUS: FAIL"]

        refused_port = free_port()
        with open(CONFIG, "w") as f:
            json.dump({"target_port": refused_port, "log_path": relative_log}, f)
        run_monitor()
        with open(correct_log) as f:
            assert f.read().splitlines() == ["SENTINEL", "STATUS: OK", "STATUS: FAIL", "STATUS: FAIL"]
        assert not os.path.exists(wrong_log)
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        try:
            os.remove(correct_log)
        except FileNotFoundError:
            pass


def recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError(f"connection closed after {len(data)} of {count} expected bytes")
        data.extend(chunk)
    return bytes(data)


def test_04_proxy_forwards_arbitrary_tcp_and_survives_sequential_disconnects():
    kill_port(9090)
    kill_port(8080)

    secret = os.urandom(21)
    greeting = os.urandom(17)
    stop = threading.Event()
    backend = socket.socket()
    backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    backend.bind(("127.0.0.1", 8080))
    backend.listen(10)
    backend.settimeout(0.2)

    def backend_loop():
        while not stop.is_set():
            try:
                conn, _ = backend.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with conn:
                conn.settimeout(3)
                try:
                    conn.sendall(greeting)
                    header = recv_exact(conn, 4)
                    size = int.from_bytes(header, "big")
                    if size > 200000:
                        continue
                    payload = recv_exact(conn, size)
                    response = hashlib.sha256(secret + payload).digest() + payload[::-1]
                    conn.sendall(response)
                except (OSError, AssertionError):
                    pass

    thread = threading.Thread(target=backend_loop, daemon=True)
    thread.start()
    proxy = subprocess.Popen(
        ["python3", "/home/user/infra/proxy.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        deadline = time.monotonic() + 5
        while not listener_pids(9090) and time.monotonic() < deadline:
            assert proxy.poll() is None, "proxy.py exited before accepting connections"
            time.sleep(0.05)
        assert listener_pids(9090), "proxy.py did not listen on 127.0.0.1:9090"

        # Cause a broken/incomplete connection, then verify later connections still work.
        broken = socket.create_connection(("127.0.0.1", 9090), timeout=2)
        broken.sendall(b"\x00\x01")
        broken.close()
        time.sleep(0.1)

        for size in (1, 257, 8193, 33333):
            payload = os.urandom(size)
            with socket.create_connection(("127.0.0.1", 9090), timeout=3) as client:
                client.settimeout(5)
                assert recv_exact(client, len(greeting)) == greeting
                client.sendall(len(payload).to_bytes(4, "big") + payload)
                expected = hashlib.sha256(secret + payload).digest() + payload[::-1]
                assert recv_exact(client, len(expected)) == expected
            assert proxy.poll() is None, "proxy.py exited after a client disconnected"
    finally:
        proxy.terminate()
        try:
            proxy.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proxy.kill()
            proxy.wait(timeout=2)
        stop.set()
        backend.close()
        thread.join(timeout=1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
