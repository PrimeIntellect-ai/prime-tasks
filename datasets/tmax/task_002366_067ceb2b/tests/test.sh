#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import secrets
import signal
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

ROOT = "/home/user/ci-system"
COMMITS = os.path.join(ROOT, "commits")
WORKSPACE = os.path.join(ROOT, "workspace")
LOGS = os.path.join(ROOT, "logs")
BACKEND_TOKEN = "REGISTRY_" + secrets.token_hex(16)
BACKEND_REQUESTS = []


def kill_executable(path):
    target = os.path.realpath(path)
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) in (1, os.getpid()):
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == target:
                os.kill(int(entry), signal.SIGKILL)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass


def kill_port_listeners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except (FileNotFoundError, PermissionError):
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.3)


def wait_for_port(port, process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Process exited before opening port {port} with code {process.returncode}")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    raise AssertionError(f"Port {port} was not opened within {timeout} seconds")


class MockRegistryHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        BACKEND_REQUESTS.append((self.path, self.headers.get("Host")))
        body = ("SECRET_DATA\n" + BACKEND_TOKEN + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope="session", autouse=True)
def running_submitted_services():
    kill_executable("/home/user/egress_proxy")
    kill_executable("/home/user/ci_runner")
    kill_port_listeners(8080)
    kill_port_listeners(9090)

    server = HTTPServer(("127.0.0.1", 9090), MockRegistryHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    proxy = subprocess.Popen(
        ["/home/user/egress_proxy"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_port(8080, proxy)

    runner = subprocess.Popen(
        ["/home/user/ci_runner"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.3)
    assert runner.poll() is None, "Submitted CI runner exited immediately"

    try:
        yield
    finally:
        for process in (runner, proxy):
            if process.poll() is None:
                process.terminate()
        for process in (runner, proxy):
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
        server.shutdown()
        server.server_close()


def test_directories_exist():
    """Verify that the required directory structure exists."""
    dirs = [COMMITS, WORKSPACE, LOGS]
    for d in dirs:
        assert os.path.exists(d), f"Directory {d} does not exist."
        assert os.path.isdir(d), f"{d} is not a directory."


def test_binaries_exist_and_executable():
    """Verify that the Go binaries and required Go source files exist."""
    pairs = [
        ("/home/user/egress_proxy", "/home/user/egress_proxy.go"),
        ("/home/user/ci_runner", "/home/user/ci_runner.go"),
    ]
    for binary, source in pairs:
        assert os.path.exists(binary), f"Binary {binary} does not exist."
        assert os.path.isfile(binary), f"Binary {binary} is not a regular file."
        assert os.access(binary, os.X_OK), f"Binary {binary} is not executable."
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable."

        metadata = subprocess.run(
            ["go", "version", "-m", binary], capture_output=True, text=True, timeout=10
        )
        assert metadata.returncode == 0 and "go1" in metadata.stdout, \
            f"{binary} is not identifiable as a compiled Go program."

        assert os.path.isfile(source), f"Required Go source {source} does not exist."
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                ["go", "build", "-o", os.path.join(tmpdir, "program"), source],
                capture_output=True,
                text=True,
                timeout=30,
                env={**os.environ, "GO111MODULE": "off"},
            )
            assert result.returncode == 0, f"Go source {source} does not compile: {result.stderr}"


def test_proxy_listening():
    """Verify that the egress proxy is listening on 127.0.0.1:8080."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        result = s.connect_ex(("127.0.0.1", 8080))
        assert result == 0, "Port 8080 is not open. Egress proxy is not listening."
    finally:
        s.close()


def proxy_request(host, path):
    connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    try:
        connection.putrequest("GET", f"http://{host}/{path}", skip_host=True)
        connection.putheader("Host", host)
        connection.endheaders()
        response = connection.getresponse()
        return response.status, response.read().decode(errors="replace")
    finally:
        connection.close()


def test_independent_proxy_requests():
    """Exercise the submitted proxy directly with unpredictable requests."""
    path = "probe-" + secrets.token_hex(12)
    before = len(BACKEND_REQUESTS)
    status, body = proxy_request("allowed-registry.local", path)
    assert status == 200, f"Allowed registry returned HTTP {status}"
    assert BACKEND_TOKEN in body, "Allowed request did not reach the verifier's registry server."
    assert len(BACKEND_REQUESTS) == before + 1, "Allowed request was not forwarded to port 9090."

    for host in ("blocked-" + secrets.token_hex(8) + ".invalid", "allowed-registry.local:80"):
        before = len(BACKEND_REQUESTS)
        status, body = proxy_request(host, "deny-" + secrets.token_hex(8))
        assert status == 403, f"Host {host!r} was not blocked; got HTTP {status}."
        assert body.strip() == "BLOCKED", f"Blocked response had incorrect body: {body!r}"
        assert len(BACKEND_REQUESTS) == before, "A blocked request was forwarded to the registry."


def remove_job_artifacts(job_name):
    for suffix in (".status", ".pid"):
        try:
            os.unlink(os.path.join(LOGS, job_name + suffix))
        except FileNotFoundError:
            pass
    workspace = os.path.join(WORKSPACE, job_name)
    if os.path.isdir(workspace):
        import shutil
        shutil.rmtree(workspace)


def wait_for_job(job_name, timeout=20):
    status_file = os.path.join(LOGS, job_name + ".status")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(status_file):
            return
        time.sleep(0.2)
    raise AssertionError(f"Status file {status_file} was not created within {timeout} seconds.")


def test_ci_runner_and_proxy_logic():
    """Retain the original fixed CI runner processing and proxy assertions."""
    job_name = "job-TEST"
    remove_job_artifacts(job_name)
    tar_path = os.path.join(COMMITS, job_name + ".tar.gz")
    try:
        os.unlink(tar_path)
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory() as tmpdir:
        ci_txt_path = os.path.join(tmpdir, "ci.txt")
        with open(ci_txt_path, "w") as f:
            f.write("sh test_script.sh\n")

        script_path = os.path.join(tmpdir, "test_script.sh")
        with open(script_path, "w") as f:
            f.write('echo "TEST" > test.out\n')
            f.write('curl -s http://allowed-registry.local/secret >> test.out\n')
            f.write('curl -s http://blocked.com/ >> test.out\n')

        with tarfile.open(tar_path, "w:gz") as tar:
            tar.add(ci_txt_path, arcname="ci.txt")
            tar.add(script_path, arcname="test_script.sh")

    wait_for_job(job_name, 15)
    status_file = os.path.join(LOGS, job_name + ".status")
    pid_file = os.path.join(LOGS, job_name + ".pid")
    workspace_dir = os.path.join(WORKSPACE, job_name)
    out_file = os.path.join(workspace_dir, "test.out")

    with open(status_file) as f:
        status = f.read().strip()
    assert status == "SUCCESS", f"Expected status SUCCESS, got {status}"

    assert os.path.exists(pid_file), f"PID file {pid_file} was not created."
    with open(pid_file) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"

    assert not os.path.exists(tar_path), f"Tarball {tar_path} was not deleted after processing."
    assert os.path.exists(out_file), f"Output file {out_file} was not created in workspace."
    with open(out_file) as f:
        output = f.read()
    assert "TEST" in output, "Output file missing 'TEST'."
    assert "SECRET_DATA" in output, "Output file missing 'SECRET_DATA' from allowed registry."
    assert "BLOCKED" in output, "Output file missing 'BLOCKED' from blocked domain."


def test_randomized_additional_jobs_and_environment():
    """Process multiple unpredictable jobs and verify command execution and proxy injection."""
    for _ in range(2):
        job_name = "job-" + secrets.token_hex(8)
        marker = "MARKER_" + secrets.token_hex(16)
        remove_job_artifacts(job_name)
        tar_path = os.path.join(COMMITS, job_name + ".tar.gz")

        with tempfile.TemporaryDirectory() as tmpdir:
            with open(os.path.join(tmpdir, "ci.txt"), "w") as f:
                f.write("sh randomized.sh\n")
            with open(os.path.join(tmpdir, "randomized.sh"), "w") as f:
                f.write(f"printf '%s\\n' '{marker}' > result.txt\n")
                f.write("printf '%s\\n' \"$http_proxy\" >> result.txt\n")
                f.write("curl -s http://allowed-registry.local/random >> result.txt\n")
                f.write("curl -s http://evil-$(date +%s%N).invalid/x >> result.txt\n")
            with tarfile.open(tar_path, "w:gz") as tar:
                tar.add(os.path.join(tmpdir, "ci.txt"), arcname="ci.txt")
                tar.add(os.path.join(tmpdir, "randomized.sh"), arcname="randomized.sh")

        wait_for_job(job_name)
        status_file = os.path.join(LOGS, job_name + ".status")
        pid_file = os.path.join(LOGS, job_name + ".pid")
        result_file = os.path.join(WORKSPACE, job_name, "result.txt")

        with open(status_file) as f:
            assert f.read().strip() == "SUCCESS"
        with open(pid_file) as f:
            assert f.read().strip().isdigit(), "Randomized job PID is not an integer."
        assert not os.path.exists(tar_path), "Randomized job tarball was not deleted."
        assert os.path.isfile(result_file), "Randomized job command did not run in its workspace."
        with open(result_file) as f:
            result = f.read()
        assert marker in result, "Randomized command output is missing."
        assert "http://127.0.0.1:8080" in result, "Build did not receive the required http_proxy value."
        assert BACKEND_TOKEN in result, "Randomized job's allowed request did not reach the registry."
        assert "BLOCKED" in result, "Randomized job's disallowed request was not blocked."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
