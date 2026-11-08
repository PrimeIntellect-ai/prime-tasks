#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import threading
import time
import pytest

PROVISION = "/home/user/provision.sh"
ENV_FILE = "/home/user/.mail_env"
HAPROXY_CFG = "/home/user/haproxy.cfg"
HEALTH_CHECK = "/home/user/health_check.sh"


def processes_with_executable(path):
    result = []
    wanted = os.path.realpath(path)
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.path.realpath(os.readlink(f"/proc/{entry}/exe"))
            if executable == wanted:
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def terminate_processes(path):
    pids = processes_with_executable(path)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and processes_with_executable(path):
        time.sleep(0.05)
    for pid in processes_with_executable(path):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def listening_socket_inodes(port):
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
    return inodes


def pid_listens_on(pid, port):
    wanted = listening_socket_inodes(port)
    if not wanted:
        return False
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except (FileNotFoundError, PermissionError):
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in wanted:
                return True
    except (FileNotFoundError, PermissionError):
        return False
    return False


@pytest.fixture(scope="session", autouse=True)
def execute_submission_from_clean_state():
    assert os.path.isfile(PROVISION), "provision.sh is missing"

    terminate_processes("/usr/sbin/haproxy")
    terminate_processes("/app/mail_worker")
    for path in (ENV_FILE, HAPROXY_CFG, HEALTH_CHECK):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        ["bash", PROVISION],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        pytest.fail("provision.sh did not finish within 20 seconds")
    assert proc.returncode == 0, (
        f"provision.sh failed with exit code {proc.returncode}\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )
    time.sleep(1)
    yield


def test_provision_script_exists():
    """Test that the provision.sh script exists."""
    assert os.path.isfile("/home/user/provision.sh"), "provision.sh is missing"


def test_mail_env_exists():
    """Test that .mail_env exists and contains the required variables."""
    env_file = "/home/user/.mail_env"
    assert os.path.isfile(env_file), ".mail_env is missing"
    with open(env_file, "r") as f:
        content = f.read()
    assert "CLUSTER_NAME=alpha_cluster" in content, "CLUSTER_NAME is not set correctly in .mail_env"
    assert "WORKER_TIMEOUT=15" in content, "WORKER_TIMEOUT is not set correctly in .mail_env"

    result = subprocess.run(
        ["bash", "-c", 'set -a; source "$1"; printf "%s\\n%s\\n" "$CLUSTER_NAME" "$WORKER_TIMEOUT"', "bash", env_file],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, ".mail_env cannot be sourced successfully"
    assert result.stdout.splitlines() == ["alpha_cluster", "15"], ".mail_env does not set the required values"

    exported = subprocess.run(
        ["bash", "-c", 'source "$1"; env', "bash", env_file],
        capture_output=True,
        text=True,
        timeout=5,
    )
    env_lines = set(exported.stdout.splitlines())
    assert "CLUSTER_NAME=alpha_cluster" in env_lines, "CLUSTER_NAME must be exported"
    assert "WORKER_TIMEOUT=15" in env_lines, "WORKER_TIMEOUT must be exported"


def test_haproxy_cfg_exists():
    """Test that haproxy.cfg was generated."""
    assert os.path.isfile("/home/user/haproxy.cfg"), "haproxy.cfg is missing"


def parse_haproxy_config():
    sections = []
    current = None
    with open(HAPROXY_CFG) as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            words = line.split()
            if words[0].lower() in {"global", "defaults", "frontend", "backend", "listen"}:
                current = {"kind": words[0].lower(), "name": words[1] if len(words) > 1 else "", "lines": []}
                sections.append(current)
            elif current is not None:
                current["lines"].append(line)
    return sections


def test_haproxy_configuration_semantics():
    check = subprocess.run(
        ["haproxy", "-c", "-f", HAPROXY_CFG],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert check.returncode == 0, f"HAProxy rejected haproxy.cfg: {check.stdout}{check.stderr}"

    sections = parse_haproxy_config()
    tuning = []
    for section in sections:
        if section["kind"] in {"global", "defaults"}:
            for line in section["lines"]:
                match = re.match(r"maxconn\s+(\d+)\s*$", line, re.I)
                if match:
                    tuning.append(int(match.group(1)))
    assert tuning and max(tuning) >= 4000, "global/defaults must configure maxconn of at least 4000"

    listeners = []
    for section in sections:
        if section["kind"] not in {"frontend", "listen"}:
            continue
        for line in section["lines"]:
            if re.match(r"bind\s+(?:127\.0\.0\.1|0\.0\.0\.0|\*|\[::\]|::)?(?::)?2525(?:\s|$)", line, re.I):
                listeners.append(section)
                break
    assert listeners, "HAProxy must bind a frontend/listen section to TCP port 2525"

    defaults_tcp = any(
        section["kind"] == "defaults" and any(re.match(r"mode\s+tcp\s*$", line, re.I) for line in section["lines"])
        for section in sections
    )

    valid_path = False
    for listener in listeners:
        explicit_modes = [line.split()[1].lower() for line in listener["lines"] if re.match(r"mode\s+\S+", line, re.I)]
        if explicit_modes:
            if explicit_modes[-1] != "tcp":
                continue
        elif not defaults_tcp:
            continue

        if listener["kind"] == "listen":
            backend = listener
        else:
            backend_name = None
            for line in listener["lines"]:
                match = re.match(r"default_backend\s+(\S+)", line, re.I)
                if match:
                    backend_name = match.group(1)
            backend = next((s for s in sections if s["kind"] == "backend" and s["name"] == backend_name), None)
            if backend is None:
                continue

        if not any(re.match(r"balance\s+roundrobin\s*$", line, re.I) for line in backend["lines"]):
            continue

        servers = []
        for line in backend["lines"]:
            match = re.match(r"server\s+\S+\s+(127\.0\.0\.1|localhost):(\d+)(?:\s|$)", line, re.I)
            if match:
                servers.append(int(match.group(2)))
        if sorted(servers) == [9001, 9002, 9003, 9004]:
            valid_path = True
            break

    assert valid_path, "port 2525 must use TCP round-robin across exactly 127.0.0.1 ports 9001-9004"


def test_required_processes_are_running_and_listening():
    haproxy_pids = processes_with_executable("/usr/sbin/haproxy")
    assert haproxy_pids, "HAProxy is not running"
    assert any(pid_listens_on(pid, 2525) for pid in haproxy_pids), "HAProxy is not the process listening on port 2525"
    assert any(
        HAPROXY_CFG.encode() in open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        for pid in haproxy_pids
    ), "running HAProxy was not launched with /home/user/haproxy.cfg"

    worker_pids = processes_with_executable("/app/mail_worker")
    assert len(worker_pids) == 4, f"expected exactly four mail_worker processes, found {len(worker_pids)}"
    assignments = []
    for pid in worker_pids:
        ports = [port for port in (9001, 9002, 9003, 9004) if pid_listens_on(pid, port)]
        assert len(ports) == 1, f"mail_worker PID {pid} is not listening on exactly one required worker port"
        assignments.extend(ports)
        environ = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
        assert b"CLUSTER_NAME=alpha_cluster" in environ, "mail_worker was not launched with CLUSTER_NAME"
        assert b"WORKER_TIMEOUT=15" in environ, "mail_worker was not launched with WORKER_TIMEOUT"
    assert sorted(assignments) == [9001, 9002, 9003, 9004], "workers must listen on ports 9001-9004"


def test_health_check_script():
    """Test that health_check.sh exists, is executable, and succeeds."""
    script_path = "/home/user/health_check.sh"
    assert os.path.isfile(script_path), "health_check.sh is missing"
    assert os.access(script_path, os.X_OK), "health_check.sh is not executable"

    result = subprocess.run(["bash", script_path], capture_output=True, timeout=10)
    assert result.returncode == 0, f"health_check.sh failed with exit code {result.returncode}"


def test_benchmark_success_rate():
    """Benchmark the HAProxy load balancer to ensure high concurrency success rate."""
    SUCCESS_COUNT = 0
    TOTAL_REQUESTS = 5000
    lock = threading.Lock()

    def attack():
        nonlocal SUCCESS_COUNT
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2.0)
            s.connect(('127.0.0.1', 2525))
            s.sendall(b"EHLO benchmark\r\n")
            data = s.recv(1024)
            if b"250" in data:
                with lock:
                    SUCCESS_COUNT += 1
            s.close()
        except Exception:
            pass

    threads = []
    for _ in range(TOTAL_REQUESTS):
        t = threading.Thread(target=attack)
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    success_rate = SUCCESS_COUNT / TOTAL_REQUESTS
    assert success_rate >= 0.99, f"Throughput test failed. Expected >= 0.99, got {success_rate} ({SUCCESS_COUNT}/{TOTAL_REQUESTS} successful)"


def run_fake_smtp(response):
    ready = threading.Event()
    received = []
    errors = []

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(("127.0.0.1", 2525))
                sock.listen(1)
                sock.settimeout(5)
                ready.set()
                conn, _ = sock.accept()
                with conn:
                    conn.settimeout(3)
                    received.append(conn.recv(4096))
                    conn.sendall(response)
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server)
    thread.start()
    assert ready.wait(2), "fake SMTP server did not start"
    assert not errors, f"fake SMTP server failed: {errors}"
    try:
        result = subprocess.run(["bash", HEALTH_CHECK], capture_output=True, timeout=6)
    except subprocess.TimeoutExpired:
        pytest.fail("health_check.sh did not terminate promptly")
    thread.join(timeout=6)
    assert not thread.is_alive(), "health check did not connect to 127.0.0.1:2525"
    assert not errors, f"fake SMTP server failed: {errors}"
    assert received, "health check sent no SMTP request"
    return result, received[0]


def test_zz_health_check_validates_the_protocol_response():
    terminate_processes("/usr/sbin/haproxy")
    deadline = time.time() + 3
    while time.time() < deadline and listening_socket_inodes(2525):
        time.sleep(0.05)
    assert not listening_socket_inodes(2525), "could not release HAProxy port for health-check validation"

    failure, request = run_fake_smtp(b"550 failure\r\n")
    assert b"EHLO benchmark" in request, "health_check.sh must send EHLO benchmark"
    assert failure.returncode == 1, "health_check.sh must exit 1 when the response is not successful"

    success, request = run_fake_smtp(b"250 OK\r\n")
    assert b"EHLO benchmark" in request, "health_check.sh must send EHLO benchmark"
    assert success.returncode == 0, "health_check.sh must exit 0 after receiving a 250 response"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
