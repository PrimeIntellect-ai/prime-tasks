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
import configparser
import os
import pwd
import re
import secrets
import socket
import subprocess
import time

import pytest
import requests

PROXY_URL = "http://127.0.0.1:8080"
EXPECTED_TOKEN = "8xG2pL9"
USER_UID = pwd.getpwnam("user").pw_uid


def wait_for_service(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def all_processes():
    result = {}
    for name in os.listdir("/proc"):
        if name.isdigit():
            pid = int(name)
            cmd = proc_cmdline(pid)
            if cmd:
                result[pid] = cmd
    return result


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        return int(data[data.rfind(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = parent_pid(pid)
    return False


def listener_inodes(port, address="127.0.0.1"):
    wanted_port = f"{port:04X}"
    wanted_addr = "0100007F" if address == "127.0.0.1" else None
    inodes = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(path).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_addr, local_port = fields[1].split(":")
            if local_port == wanted_port and fields[3] == "0A":
                if wanted_addr is None or local_addr == wanted_addr:
                    inodes.add(fields[9])
    return inodes


def pids_holding_inodes(inodes):
    holders = set()
    if not inodes:
        return holders
    for pid in all_processes():
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                holders.add(pid)
                break
    return holders


def strip_config_comments(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def test_required_artifacts_and_configuration():
    for path in ("/home/user/backend.py", "/home/user/nginx.conf", "/home/user/supervisord.conf"):
        assert os.path.isfile(path), f"Required artifact is missing or not a regular file: {path}"
        assert os.path.getsize(path) > 0, f"Required artifact is empty: {path}"

    nginx_text = strip_config_comments(open("/home/user/nginx.conf").read())
    assert re.search(r"\bdaemon\s+off\s*;", nginx_text), "nginx.conf must set daemon off"
    assert re.search(r"\bpid\s+/home/user/nginx\.pid\s*;", nginx_text), "nginx pid path is incorrect"
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080(?:\s+[^;]*)?;", nginx_text), "nginx is not configured to listen on 127.0.0.1:8080"
    assert re.search(r"\bserver\s+127\.0\.0\.1:9001(?:\s+[^;]*)?;", nginx_text), "backend 9001 is absent from nginx upstreams"
    assert re.search(r"\bserver\s+127\.0\.0\.1:9002(?:\s+[^;]*)?;", nginx_text), "backend 9002 is absent from nginx upstreams"
    assert re.search(r"\bproxy_pass\s+http://[^;]+;", nginx_text), "nginx.conf does not proxy requests"
    assert re.search(r"\baccess_log\s+/home/user/proxy_access\.log(?:\s+[^;]*)?;", nginx_text), "nginx access log path is incorrect"
    assert re.search(r"\berror_log\s+/home/user/proxy_error\.log(?:\s+[^;]*)?;", nginx_text), "nginx error log path is incorrect"

    cfg = configparser.RawConfigParser(interpolation=None)
    cfg.read("/home/user/supervisord.conf")
    for name, port in (("backend1", "9001"), ("backend2", "9002")):
        section = f"program:{name}"
        assert cfg.has_section(section), f"Missing [{section}]"
        command = cfg.get(section, "command", fallback="")
        assert "/home/user/backend.py" in command and re.search(rf"(?:^|\s){port}(?:\s|$)", command), f"{name} does not run backend.py on {port}"
    assert cfg.has_section("program:proxy"), "Missing [program:proxy]"
    proxy_command = cfg.get("program:proxy", "command", fallback="")
    assert "nginx" in proxy_command and "/home/user/nginx.conf" in proxy_command, "proxy does not run nginx with nginx.conf"


def test_supervised_runtime_architecture():
    processes = all_processes()
    supervisors = [pid for pid, cmd in processes.items() if "supervisord" in cmd and "/home/user/supervisord.conf" in cmd]
    assert supervisors, "No supervisord process using /home/user/supervisord.conf is running"
    supervisor = supervisors[0]
    assert proc_uid(supervisor) == USER_UID, "supervisord is not running as the unprivileged user"

    status = subprocess.run(
        ["supervisorctl", "-c", "/home/user/supervisord.conf", "status"],
        text=True, capture_output=True, timeout=5
    )
    assert status.returncode == 0, f"supervisorctl failed: {status.stdout} {status.stderr}"
    for name in ("backend1", "backend2", "proxy"):
        assert re.search(rf"(?m)^{name}\s+RUNNING\b", status.stdout), f"{name} is not RUNNING under supervisord: {status.stdout}"

    for port in (9001, 9002):
        holders = pids_holding_inodes(listener_inodes(port))
        valid = []
        for pid in holders:
            cmd = processes.get(pid, proc_cmdline(pid))
            if ("/home/user/backend.py" in cmd and str(port) in cmd and
                    proc_uid(pid) == USER_UID and is_descendant(pid, supervisor)):
                valid.append(pid)
        assert valid, f"Port {port} is not served by the supervised unprivileged backend.py process"

    nginx_holders = pids_holding_inodes(listener_inodes(8080))
    valid_nginx = []
    for pid in nginx_holders:
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            exe = ""
        if exe == "nginx" and proc_uid(pid) == USER_UID and is_descendant(pid, supervisor):
            valid_nginx.append(pid)
    assert valid_nginx, "127.0.0.1:8080 is not served by supervised nginx running as user"


def test_backend_artifact_accepts_arguments_and_implements_protocol():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    token = "verify-" + secrets.token_hex(12)

    def demote():
        os.setgid(pwd.getpwnam("user").pw_gid)
        os.setuid(USER_UID)

    proc = subprocess.Popen(
        ["python3", "/home/user/backend.py", str(port), token],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=demote
    )
    base = f"http://127.0.0.1:{port}"
    try:
        assert wait_for_service(base + "/status", timeout=5), "backend.py did not start when invoked with port and token arguments"
        status = requests.get(base + "/status", timeout=2)
        assert status.status_code == 200
        assert status.json() == {"status": "ok"}
        assert status.headers.get("X-Backend-Port") == str(port)

        denied = requests.get(base + "/users", headers={"X-Admin-Token": token + "-wrong"}, timeout=2)
        assert denied.status_code == 401
        assert denied.headers.get("X-Backend-Port") == str(port)

        allowed = requests.get(base + "/users", headers={"X-Admin-Token": token}, timeout=2)
        assert allowed.status_code == 200
        assert allowed.json() == {"users": ["alice", "bob", "charlie"]}
        assert allowed.headers.get("X-Backend-Port") == str(port)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_direct_backend_instances():
    for port in (9001, 9002):
        base = f"http://127.0.0.1:{port}"
        status = requests.get(base + "/status", timeout=2)
        assert status.status_code == 200
        assert status.json() == {"status": "ok"}
        assert status.headers.get("X-Backend-Port") == str(port)

        denied = requests.get(base + "/users", headers={"X-Admin-Token": "not-the-token"}, timeout=2)
        assert denied.status_code == 401
        assert denied.headers.get("X-Backend-Port") == str(port)

        allowed = requests.get(base + "/users", headers={"X-Admin-Token": EXPECTED_TOKEN}, timeout=2)
        assert allowed.status_code == 200
        assert allowed.json() == {"users": ["alice", "bob", "charlie"]}
        assert allowed.headers.get("X-Backend-Port") == str(port)


def test_status_and_load_balancing():
    """Verify /status endpoint and round-robin load balancing."""
    assert wait_for_service(f"{PROXY_URL}/status"), f"Service at {PROXY_URL}/status is not reachable"

    resp1 = requests.get(f"{PROXY_URL}/status")
    assert resp1.status_code == 200, f"Expected HTTP 200, got {resp1.status_code}"
    assert resp1.json() == {"status": "ok"}, f"Expected {{'status': 'ok'}}, got {resp1.json()}"
    port1 = resp1.headers.get("X-Backend-Port")
    assert port1 in ["9001", "9002"], f"Expected X-Backend-Port to be 9001 or 9002, got {port1}"

    resp2 = requests.get(f"{PROXY_URL}/status")
    assert resp2.status_code == 200, f"Expected HTTP 200, got {resp2.status_code}"
    assert resp2.json() == {"status": "ok"}
    port2 = resp2.headers.get("X-Backend-Port")
    assert port2 in ["9001", "9002"], f"Expected X-Backend-Port to be 9001 or 9002, got {port2}"
    assert port1 != port2, f"Load balancing failed: both requests hit port {port1}. Expected round-robin between 9001 and 9002."


def test_users_unauthorized():
    """Verify /users endpoint without token returns 401."""
    resp = requests.get(f"{PROXY_URL}/users")
    assert resp.status_code == 401, f"Expected HTTP 401 Unauthorized for missing token, got {resp.status_code}"


def test_users_authorized():
    """Verify /users endpoint with correct token returns 200 and user list."""
    headers = {"X-Admin-Token": EXPECTED_TOKEN}
    resp = requests.get(f"{PROXY_URL}/users", headers=headers)
    assert resp.status_code == 200, f"Expected HTTP 200 for valid token, got {resp.status_code}"
    expected_data = {"users": ["alice", "bob", "charlie"]}
    assert resp.json() == expected_data, f"Expected {expected_data}, got {resp.json()}"


def test_proxy_access_log():
    """Verify that the Nginx access log exists and contains entries."""
    log_path = "/home/user/proxy_access.log"
    assert os.path.isfile(log_path), f"Access log not found at {log_path}"
    assert os.path.getsize(log_path) > 0, f"Access log at {log_path} is empty"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
