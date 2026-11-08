#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import threading
import time
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

PROXY_SOURCE = "/home/user/proxy.go"
PROXY_BINARY = "/home/user/proxy"
SUPERVISOR = "/home/user/supervise.sh"
LOG_FILE = "/home/user/logs/app.log"
BUILT_FROM_SOURCE = "/tmp/proxy_built_from_source"


def check_http_proxy(expected="MIGRATION_AUTH_9921_ACCEPTED", timeout=2):
    try:
        response = requests.get("http://127.0.0.1:8080/legacy-status", timeout=timeout)
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        assert response.text == expected, f"Unexpected response body: {response.text}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP proxy request failed: {e}")


def check_tcp_healthcheck():
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=2) as s:
            data = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
            assert data == b"HEALTHY\n", f"Unexpected TCP response: {data}"
    except Exception as e:
        pytest.fail(f"TCP healthcheck failed: {e}")


def get_pids(pattern):
    try:
        output = subprocess.check_output(["pgrep", "-f", pattern], text=True)
        return [int(pid) for pid in output.strip().split()]
    except subprocess.CalledProcessError:
        return []


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def supervisor_pids():
    result = []
    for name in os.listdir("/proc"):
        if name.isdigit() and SUPERVISOR in process_cmdline(int(name)):
            result.append(int(name))
    return result


def process_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    return {
        item.split(b"=", 1)[0].decode(errors="replace"): item.split(b"=", 1)[1].decode(errors="replace")
        for item in entries if b"=" in item
    }


def process_socket_inodes(pids):
    inodes = set()
    for pid in pids:
        fd_dir = f"/proc/{pid}/fd"
        try:
            names = os.listdir(fd_dir)
        except OSError:
            continue
        for name in names:
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                inodes.add(target[8:-1])
    return inodes


def listening_socket_entries():
    entries = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    address, port_hex = fields[1].rsplit(":", 1)
                    entries.append((address, int(port_hex, 16), fields[9], table))
        except OSError:
            pass
    return entries


def assert_listener(pids, port, address):
    inodes = process_socket_inodes(pids)
    matches = [e for e in listening_socket_entries() if e[1] == port and e[2] in inodes]
    assert matches, f"Process does not own a listening socket on port {port}"
    assert any(e[0] == address and e[3].endswith("/tcp") for e in matches), (
        f"Port {port} is not bound to the required IPv4 address; found {matches}"
    )


def assert_log_fds(pids):
    assert os.path.isfile(LOG_FILE), f"Missing log file {LOG_FILE}"
    expected = os.path.realpath(LOG_FILE)
    for pid in pids:
        for fd in (1, 2):
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
            assert os.path.realpath(target) == expected, (
                f"PID {pid} fd {fd} is not redirected to {LOG_FILE}: {target}"
            )
            with open(f"/proc/{pid}/fdinfo/{fd}") as info:
                flags_line = next(line for line in info if line.startswith("flags:"))
            flags = int(flags_line.split()[1], 8)
            assert flags & os.O_APPEND, f"PID {pid} fd {fd} is not opened in append mode"


def wait_until(predicate, timeout=3.0, interval=0.05):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise last_error
    raise AssertionError("Condition was not satisfied before timeout")


def test_required_artifacts_and_source():
    assert os.path.isfile(PROXY_SOURCE), f"Missing Go source {PROXY_SOURCE}"
    assert os.path.isfile(PROXY_BINARY), f"Missing proxy binary {PROXY_BINARY}"
    assert os.access(PROXY_BINARY, os.X_OK), f"Proxy binary is not executable: {PROXY_BINARY}"
    with open(PROXY_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled proxy is not an ELF executable"

    assert os.path.isfile(SUPERVISOR), f"Missing supervisor {SUPERVISOR}"
    assert os.access(SUPERVISOR, os.X_OK), f"Supervisor is not executable: {SUPERVISOR}"
    subprocess.run(["bash", "-n", SUPERVISOR], check=True, timeout=5)
    subprocess.run(
        ["go", "build", "-o", BUILT_FROM_SOURCE, PROXY_SOURCE],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_services_running():
    check_http_proxy()
    check_tcp_healthcheck()


def test_process_configuration_bindings_and_logging():
    legacy_pids = get_pids("/app/legacy_api")
    proxy_pids = get_pids(PROXY_BINARY)
    assert legacy_pids, "legacy_api is not running"
    assert proxy_pids, "proxy is not running"

    for pid in legacy_pids:
        env = process_environment(pid)
        assert env.get("TZ") == "UTC", f"legacy_api PID {pid} is missing TZ=UTC"
        assert env.get("LC_ALL") == "C", f"legacy_api PID {pid} is missing LC_ALL=C"

    assert_listener(proxy_pids, 8080, "00000000")
    assert_listener(proxy_pids, 8081, "00000000")
    assert_listener(legacy_pids, 9090, "0100007F")
    assert_log_fds(legacy_pids + proxy_pids)


def test_supervision_resilience():
    legacy_pids = get_pids("/app/legacy_api")
    proxy_pids = get_pids(PROXY_BINARY)
    assert legacy_pids, "legacy_api is not running"
    assert proxy_pids, "proxy is not running"

    for pid in legacy_pids + proxy_pids:
        try:
            os.kill(pid, 9)
        except OSError:
            pass

    time.sleep(3)

    new_legacy_pids = get_pids("/app/legacy_api")
    new_proxy_pids = get_pids(PROXY_BINARY)
    assert new_legacy_pids, "legacy_api was not restarted by the supervisor"
    assert new_proxy_pids, "proxy was not restarted by the supervisor"
    assert not set(legacy_pids) & set(new_legacy_pids), "legacy_api PID did not change after SIGKILL"
    assert not set(proxy_pids) & set(new_proxy_pids), "proxy PID did not change after SIGKILL"

    check_http_proxy()
    check_tcp_healthcheck()

    for pid in new_legacy_pids:
        env = process_environment(pid)
        assert env.get("TZ") == "UTC", f"restarted legacy_api PID {pid} is missing TZ=UTC"
        assert env.get("LC_ALL") == "C", f"restarted legacy_api PID {pid} is missing LC_ALL=C"
    assert_listener(new_proxy_pids, 8080, "00000000")
    assert_listener(new_proxy_pids, 8081, "00000000")
    assert_log_fds(new_legacy_pids + new_proxy_pids)


def test_quota_management():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "ab") as f:
        f.write(os.urandom(600 * 1024))

    time.sleep(4)

    if os.path.exists(LOG_FILE):
        size = os.path.getsize(LOG_FILE)
        assert size < 50 * 1024, f"Log file was not truncated, size is {size} bytes"


def test_real_forwarding_and_built_source_behavior():
    nonce = "DYNAMIC_" + secrets.token_hex(24)
    seen_paths = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            seen_paths.append(self.path)
            if self.path == "/secret_token_v2":
                body = nonce.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                body = b"WRONG_LEGACY_PATH"
                self.send_response(404)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def log_message(self, format, *args):
            pass

    stopped = []
    fake_legacy = None
    fake_thread = None
    source_proxy = None
    try:
        stopped = supervisor_pids()
        assert stopped, "No running supervisor process found"
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGSTOP)
            except OSError:
                pass

        for pid in get_pids("/app/legacy_api"):
            try:
                os.kill(pid, 9)
            except OSError:
                pass

        def start_fake():
            nonlocal fake_legacy, fake_thread
            fake_legacy = ThreadingHTTPServer(("127.0.0.1", 9090), Handler)
            fake_thread = threading.Thread(target=fake_legacy.serve_forever, daemon=True)
            fake_thread.start()
            return True

        wait_until(start_fake, timeout=3)

        # The submitted executable must obtain a verifier-generated value from
        # the real legacy address and endpoint rather than return a fixed token.
        wait_until(lambda: (check_http_proxy(nonce) or True), timeout=3)
        assert "/secret_token_v2" in seen_paths, "Proxy did not request the legacy token endpoint"
        check_tcp_healthcheck()

        # The required Go source must build into a service with the same behavior.
        for pid in get_pids(PROXY_BINARY):
            try:
                os.kill(pid, 9)
            except OSError:
                pass
        wait_until(lambda: not get_pids(PROXY_BINARY), timeout=2)

        source_proxy = subprocess.Popen(
            [BUILT_FROM_SOURCE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_until(lambda: (check_http_proxy(nonce) or True), timeout=3)
        check_tcp_healthcheck()
        assert source_proxy.poll() is None, "Proxy built from proxy.go exited unexpectedly"
    finally:
        if source_proxy is not None and source_proxy.poll() is None:
            source_proxy.kill()
            source_proxy.wait(timeout=2)
        if fake_legacy is not None:
            fake_legacy.shutdown()
            fake_legacy.server_close()
        if fake_thread is not None:
            fake_thread.join(timeout=2)
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except OSError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
