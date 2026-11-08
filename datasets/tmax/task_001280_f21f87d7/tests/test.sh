#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

SETUP_SCRIPT = "/home/user/setup_tunnel.py"
LOAD_SCRIPT = "/home/user/load_test.py"
NGINX_CONFIG = "/home/user/nginx/nginx.conf"


class BackendState:
    def __init__(self):
        self.lock = threading.Lock()
        self.total = 0
        self.active = 0
        self.max_active = 0
        self.success_limit = None

    def reset(self, success_limit=None):
        with self.lock:
            self.total = 0
            self.active = 0
            self.max_active = 0
            self.success_limit = success_limit

    def begin(self):
        with self.lock:
            self.total += 1
            request_number = self.total
            self.active += 1
            self.max_active = max(self.max_active, self.active)
            limit = self.success_limit
        return request_number, limit

    def end(self):
        with self.lock:
            self.active -= 1


BACKEND = BackendState()


class BackendHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        request_number, success_limit = BACKEND.begin()
        try:
            # Keep requests outstanding long enough to detect real concurrency.
            time.sleep(0.5)
            success = success_limit is None or request_number <= success_limit
            body = b"verified-mock-backend\n" if success else b"injected-failure\n"
            self.send_response(200 if success else 503)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
        finally:
            BACKEND.end()

    def log_message(self, fmt, *args):
        pass


class BackendServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 256
    allow_reuse_address = True


def kill_port(port):
    subprocess.run(
        ["fuser", "-k", f"{port}/tcp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    deadline = time.time() + 3
    while time.time() < deadline:
        with socket.socket() as sock:
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return
        time.sleep(0.05)


def wait_for_port(port, listening=True, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as sock:
            open_now = sock.connect_ex(("127.0.0.1", port)) == 0
        if open_now == listening:
            return
        time.sleep(0.05)
    raise AssertionError(f"Port {port} did not reach expected listening={listening} state")


def run_as_user(argv, timeout=15):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "USER=user"] + argv,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def read_master_pid():
    with open("/home/user/nginx/nginx.pid") as f:
        return int(f.read().strip())


def process_start_time(pid):
    with open(f"/proc/{pid}/stat") as f:
        return f.read().split()[21]


def tunnel_processes():
    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                parts = [p.decode(errors="replace") for p in f.read().split(b"\0") if p]
            if not parts or os.path.basename(parts[0]) != "ssh":
                continue
            command = " ".join(parts)
            if re.search(r"9042:(?:localhost|127\.0\.0\.1):8000", command):
                uid = os.stat(f"/proc/{entry}").st_uid
                matches.append((int(entry), uid, command))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return matches


def run_submission(path, timeout=15):
    result = run_as_user(["python3", path], timeout=timeout)
    assert result.returncode == 0, (
        f"Executing {path} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def prepared_environment():
    for path in (SETUP_SCRIPT, LOAD_SCRIPT):
        assert os.path.exists(path), f"Expected script missing at {path}"
        assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"{path} is not a regular file"
        compile(open(path, "rb").read(), path, "exec")

    assert os.path.exists(NGINX_CONFIG), f"Nginx config missing at {NGINX_CONFIG}"
    with open(NGINX_CONFIG) as f:
        submitted_config = f.read()

    proxy_pattern = re.compile(
        r"proxy_pass\s+http://(?:localhost|127\.0\.0\.1):9042\s*;",
        re.IGNORECASE,
    )
    assert "9042" in submitted_config, "Nginx config does not contain the documented port 9042"
    assert proxy_pattern.search(submitted_config), (
        "The /api proxy_pass must target localhost port 9042"
    )
    assert re.search(
        r"location\s+(?:=\s*)?/api\b[^{]*\{[^}]*proxy_pass\s+http://(?:localhost|127\.0\.0\.1):9042\s*;",
        submitted_config,
        re.IGNORECASE | re.DOTALL,
    ), "The localhost:9042 proxy_pass is not configured in the /api location"

    # Remove any arbitrary listeners left by a submission, then provide the
    # prerequisites described by the task.
    for port in (8080, 9042, 8000):
        kill_port(port)

    subprocess.run(["pkill", "-x", "sshd"], check=False)
    os.makedirs("/var/run/sshd", exist_ok=True)
    subprocess.run(["chown", "-R", "user:user", "/home/user/.ssh"], check=True)
    os.chmod("/home/user/.ssh", 0o700)
    os.chmod("/home/user/.ssh/authorized_keys", 0o600)
    os.chmod("/home/user/.ssh/id_rsa", 0o600)
    sshd = subprocess.run(["/usr/sbin/sshd"], text=True, capture_output=True)
    assert sshd.returncode == 0, f"Could not start sshd: {sshd.stderr}"
    wait_for_port(22)

    backend_server = BackendServer(("127.0.0.1", 8000), BackendHandler)
    backend_thread = threading.Thread(target=backend_server.serve_forever, daemon=True)
    backend_thread.start()
    wait_for_port(8000)

    try:
        # Start Nginx with a stale in-memory proxy target, then restore the
        # submitted file. A successful request after setup_tunnel.py runs thus
        # requires that the script reload the existing master process.
        stale_config, replacements = proxy_pattern.subn(
            "proxy_pass http://localhost:9999;", submitted_config, count=1
        )
        assert replacements == 1
        with open(NGINX_CONFIG, "w") as f:
            f.write(stale_config)
        subprocess.run(["chown", "user:user", NGINX_CONFIG], check=True)

        syntax = run_as_user(["nginx", "-t", "-c", NGINX_CONFIG])
        assert syntax.returncode == 0, f"Invalid Nginx configuration: {syntax.stderr}"
        started = run_as_user(["nginx", "-c", NGINX_CONFIG])
        assert started.returncode == 0, f"Could not start Nginx: {started.stderr}"
        wait_for_port(8080)
        original_pid = read_master_pid()
        original_start = process_start_time(original_pid)

        with open(NGINX_CONFIG, "w") as f:
            f.write(submitted_config)
        subprocess.run(["chown", "user:user", NGINX_CONFIG], check=True)

        run_submission(SETUP_SCRIPT)
        wait_for_port(9042)
        time.sleep(0.3)

        assert read_master_pid() == original_pid, "setup_tunnel.py restarted Nginx instead of reloading it"
        assert process_start_time(original_pid) == original_start, "Nginx master process was replaced"

        tunnels_after_first = tunnel_processes()
        assert len(tunnels_after_first) == 1, (
            "Expected exactly one user-owned SSH local-forward process for "
            "9042 -> localhost:8000"
        )
        assert tunnels_after_first[0][1] == 1000 or tunnels_after_first[0][1] == os.stat("/home/user").st_uid

        with urllib.request.urlopen("http://127.0.0.1:8080/api", timeout=5) as response:
            body = response.read()
            assert response.status == 200
            assert body == b"verified-mock-backend\n", "Response did not come from the mock backend through the tunnel"

        # Execute it again and require stable processes and service state.
        run_submission(SETUP_SCRIPT)
        time.sleep(0.3)
        assert read_master_pid() == original_pid, "Second execution restarted Nginx"
        assert process_start_time(original_pid) == original_start
        assert tunnel_processes() == tunnels_after_first, (
            "setup_tunnel.py is not idempotent; a second execution changed or duplicated the tunnel"
        )

        yield
    finally:
        backend_server.shutdown()
        backend_server.server_close()


def test_setup_tunnel_script_exists():
    assert os.path.exists(SETUP_SCRIPT), f"Expected script missing at {SETUP_SCRIPT}"
    assert os.path.isfile(SETUP_SCRIPT), f"{SETUP_SCRIPT} is not a file"


def test_load_test_script_exists():
    assert os.path.exists(LOAD_SCRIPT), f"Expected script missing at {LOAD_SCRIPT}"
    assert os.path.isfile(LOAD_SCRIPT), f"{LOAD_SCRIPT} is not a file"


def test_nginx_config_updated():
    assert os.path.exists(NGINX_CONFIG), f"Nginx config missing at {NGINX_CONFIG}"
    with open(NGINX_CONFIG) as f:
        content = f.read()
    assert "9042" in content, "Nginx config does not appear to use the correct port (9042)"


def test_port_9042_listening():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        assert sock.connect_ex(("localhost", 9042)) == 0, "Tunnel is not listening on port 9042"
    assert len(tunnel_processes()) == 1, "Port 9042 is not provided by the required SSH tunnel"


def test_nginx_api_returns_200():
    with urllib.request.urlopen("http://localhost:8080/api", timeout=5) as response:
        assert response.getcode() == 200
        assert response.read() == b"verified-mock-backend\n"


def parse_single_rate(result, path):
    assert result.returncode == 0, (
        f"Executing {path} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert len(output.splitlines()) == 1, f"{path} must output exactly one number; got {output!r}"
    try:
        return float(output)
    except ValueError:
        pytest.fail(f"Output of {path} could not be parsed as a float. Output was: {output!r}")


def execute_load_test():
    try:
        return run_as_user(["python3", LOAD_SCRIPT], timeout=20)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Executing {LOAD_SCRIPT} timed out after 20 seconds")


def assert_hundred_concurrent_requests():
    with BACKEND.lock:
        total = BACKEND.total
        maximum = BACKEND.max_active
    assert total == 100, f"Expected exactly 100 backend requests, observed {total}"
    assert maximum >= 80, (
        f"Requests were not issued as 100 concurrent requests; only {maximum} were observed in flight"
    )


def test_load_test_success_rate():
    # Derive a nontrivial expected answer instead of trusting a hard-coded 1.0.
    BACKEND.reset(success_limit=73)
    rate = parse_single_rate(execute_load_test(), LOAD_SCRIPT)
    assert_hundred_concurrent_requests()
    assert abs(rate - 0.73) < 1e-9, f"Expected measured success rate 0.73, got {rate}"

    # Preserve the original all-success assertion as well.
    BACKEND.reset(success_limit=None)
    success_rate = parse_single_rate(execute_load_test(), LOAD_SCRIPT)
    assert_hundred_concurrent_requests()
    assert success_rate >= 1.0, f"Expected success_rate >= 1.0, got {success_rate}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
