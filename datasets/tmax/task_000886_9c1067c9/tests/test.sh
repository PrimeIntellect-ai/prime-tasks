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
import time

import pytest
import requests

HTTP_PORT = 8123
TCP_PORT = 9321
TOKEN = "secure-infra-xyz"
GATEWAY = "/home/user/gateway.py"
SUPERVISOR = "/home/user/supervise.sh"
LOG_FILE = "/home/user/logs/gateway.log"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                    result.add(int(entry))
                    break
        except OSError:
            continue
    return result


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        pid = parent_pid(pid)
        if pid == ancestor:
            return True
    return False


def kill_pid(pid):
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def clean_existing_services():
    own_ancestors = set()
    pid = os.getpid()
    while pid > 1 and pid not in own_ancestors:
        own_ancestors.add(pid)
        pid = parent_pid(pid)

    for _ in range(3):
        victims = set(listener_pids(HTTP_PORT)) | set(listener_pids(TCP_PORT))
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            candidate = int(entry)
            if candidate in own_ancestors:
                continue
            cmdline = process_cmdline(candidate)
            if GATEWAY in cmdline or SUPERVISOR in cmdline:
                victims.add(candidate)
        for victim in victims:
            kill_pid(victim)
        time.sleep(0.2)


def probe_services():
    try:
        response = requests.get(
            f"http://127.0.0.1:{HTTP_PORT}/health",
            headers={"Authorization": f"Bearer {TOKEN}"},
            timeout=0.5,
        )
        if response.status_code != 200 or response.json().get("status") != "ok":
            return False
        with socket.create_connection(("127.0.0.1", TCP_PORT), timeout=0.5) as s:
            s.sendall(b"supervision probe\n")
            if s.recv(1024) != b"ACK: supervision probe\n":
                return False
        return True
    except Exception:
        return False


def wait_for_services(supervisor, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert supervisor.poll() is None, "supervise.sh exited instead of monitoring gateway.py"
        if probe_services():
            http_pids = listener_pids(HTTP_PORT)
            tcp_pids = listener_pids(TCP_PORT)
            if http_pids and tcp_pids:
                return http_pids, tcp_pids
        time.sleep(0.1)
    pytest.fail("Services did not become ready under supervise.sh")


def assert_supervised_gateway_processes(supervisor, pids):
    assert pids, "No gateway listener processes were found"
    for pid in pids:
        assert pid != supervisor.pid and is_descendant(pid, supervisor.pid), (
            f"Listener PID {pid} was not launched and monitored by supervise.sh"
        )
        assert GATEWAY in process_cmdline(pid), (
            f"Listener PID {pid} is not executing {GATEWAY}"
        )
        for fd in (1, 2):
            try:
                assert os.path.samefile(f"/proc/{pid}/fd/{fd}", LOG_FILE), (
                    f"gateway.py file descriptor {fd} is not redirected to {LOG_FILE}"
                )
            except (FileNotFoundError, OSError):
                pytest.fail(f"Could not verify gateway.py file descriptor {fd} redirection")


@pytest.fixture(scope="module", autouse=True)
def supervised_gateway():
    clean_existing_services()
    supervisor = None
    try:
        supervisor = subprocess.Popen(
            [SUPERVISOR],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        http_pids, tcp_pids = wait_for_services(supervisor)
        initial_pids = http_pids | tcp_pids
        assert_supervised_gateway_processes(supervisor, initial_pids)

        # Simulate a gateway crash and require the same supervisor to restart it.
        for pid in initial_pids:
            kill_pid(pid)
        time.sleep(0.2)
        assert supervisor.poll() is None, "Supervisor exited when gateway.py crashed"

        new_http_pids, new_tcp_pids = wait_for_services(supervisor)
        restarted_pids = new_http_pids | new_tcp_pids
        assert restarted_pids.isdisjoint(initial_pids), "gateway.py was not restarted after being killed"
        assert_supervised_gateway_processes(supervisor, restarted_pids)
        yield
    finally:
        if supervisor is not None:
            try:
                os.killpg(supervisor.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def test_logs_directory_exists():
    assert os.path.isdir("/home/user/logs/"), "The log directory /home/user/logs/ was not created."


def test_scripts_exist_and_executable():
    assert os.path.isfile(GATEWAY), f"Gateway script missing at {GATEWAY}."
    assert os.path.isfile(SUPERVISOR), f"Supervisor script missing at {SUPERVISOR}."
    assert os.access(GATEWAY, os.X_OK), f"Gateway script {GATEWAY} is not executable."
    assert os.access(SUPERVISOR, os.X_OK), f"Supervisor script {SUPERVISOR} is not executable."


def test_http_service_health_authorized():
    url = "http://127.0.0.1:8123/health"
    headers = {"Authorization": "Bearer secure-infra-xyz"}
    try:
        response = requests.get(url, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
        assert data.get("status") == "ok", f"Expected JSON {{'status': 'ok'}}, got {data}"
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")


def test_http_service_health_unauthorized():
    url = "http://127.0.0.1:8123/health"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url}: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing token, got {response.status_code}"


def test_tcp_echo_service():
    host = "127.0.0.1"
    port = 9321
    message = "test message\n"
    expected_response = "ACK: test message\n"

    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(message.encode("utf-8"))
            response = s.recv(1024).decode("utf-8")
            assert response == expected_response, f"Expected TCP response '{expected_response}', got '{response}'"
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        pytest.fail(f"Failed to connect or communicate with TCP service at {host}:{port}: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
