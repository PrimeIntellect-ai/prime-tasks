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
import re
import stat
import smtplib
import socket
import subprocess
import time
import uuid
import signal
import requests

PROFILE = "/home/user/.bash_profile"
START_SCRIPT = "/home/user/start_services.sh"
RUN_DIR = "/home/user/run"
LOG_PATH = "/home/user/mail_sink.log"


def read_pid(name):
    path = os.path.join(RUN_DIR, name)
    assert os.path.exists(path), f"PID file {path} does not exist."
    with open(path, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file {path} does not contain a valid numeric PID."
    pid = int(value)
    assert pid > 1, f"PID file {path} contains unsafe PID {pid}."
    try:
        os.kill(pid, 0)
    except OSError as e:
        raise AssertionError(f"PID {pid} from {path} is not a live process: {e}")
    return pid


def tcp_entries():
    entries = []
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_hex, local_port_hex = fields[1].split(":")
            remote_hex, remote_port_hex = fields[2].split(":")
            entries.append({
                "local_addr": local_hex,
                "local_port": int(local_port_hex, 16),
                "remote_addr": remote_hex,
                "remote_port": int(remote_port_hex, 16),
                "state": fields[3],
                "inode": fields[9],
            })
    return entries


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return result
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def descendants(pid):
    found = {pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) in found:
                continue
            try:
                with open(f"/proc/{name}/status", "r") as f:
                    status = f.read()
                match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
                if match and int(match.group(1)) in found:
                    found.add(int(name))
                    changed = True
            except OSError:
                pass
    return found


def assert_listener_owned(pid, port, address_hex, label):
    inodes = pid_socket_inodes(pid)
    matches = [
        entry for entry in tcp_entries()
        if entry["state"] == "0A"
        and entry["local_port"] == port
        and entry["local_addr"] == address_hex
        and entry["inode"] in inodes
    ]
    assert matches, (
        f"PID {pid} from {label}.pid does not own the required listener "
        f"on address {address_hex}, port {port}."
    )


def assert_runtime():
    backend = read_pid("backend.pid")
    proxy = read_pid("proxy.pid")
    health = read_pid("health.pid")
    assert len({backend, proxy, health}) == 3, "Backend, proxy, and health PID files must identify distinct processes."
    assert_listener_owned(backend, 8025, "0100007F", "backend")
    assert_listener_owned(proxy, 2525, "00000000", "proxy")
    assert_listener_owned(health, 8080, "00000000", "health")
    return backend, proxy, health


def wait_for_runtime(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return assert_runtime()
        except (AssertionError, OSError) as e:
            last_error = e
            time.sleep(0.2)
    raise AssertionError(f"Services did not reach the required running state: {last_error}")


def stop_declared_services(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in pids):
            break
        time.sleep(0.1)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    for name in ("backend.pid", "proxy.pid", "health.pid"):
        try:
            os.remove(os.path.join(RUN_DIR, name))
        except FileNotFoundError:
            pass


def send_message(port, sender, recipient, body):
    server = smtplib.SMTP("127.0.0.1", port, timeout=5)
    try:
        server.ehlo("verifier.local")
        server.sendmail(sender, [recipient], f"Subject: runtime-{body}\r\n\r\n{body}")
        server.quit()
    finally:
        try:
            server.close()
        except Exception:
            pass


def test_complete_configuration_and_runtime():
    assert os.path.exists(PROFILE), f"File {PROFILE} does not exist."
    with open(PROFILE, "r") as f:
        content = f.read()
    assert re.search(r'^export\s+BACKEND_PORT=[\'\"]?8025[\'\"]?(?:\s|$)', content, re.MULTILINE), \
        f"Could not find 'export BACKEND_PORT=8025' in {PROFILE}"

    assert os.path.exists(START_SCRIPT), f"Script {START_SCRIPT} does not exist."
    st = os.stat(START_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {START_SCRIPT} is not executable."
    assert os.path.isdir(RUN_DIR), f"Directory {RUN_DIR} does not exist."

    # Validate that the initially supplied PID files name the actual three listeners.
    initial_pids = assert_runtime()

    # Exercise the required lifecycle manager rather than trusting the pre-existing state.
    stop_declared_services(initial_pids)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user",
         "bash", "--login", "-c", START_SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=8,
    )
    assert result.returncode == 0, f"{START_SCRIPT} exited with status {result.returncode}."
    backend_pid, proxy_pid, health_pid = wait_for_runtime()

    try:
        response = requests.get("http://127.0.0.1:8080/health", timeout=2)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f"Failed to connect to health check endpoint on port 8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Health check response is not valid JSON: {response.text}")
    assert data.get("status") == "healthy", f"Expected status 'healthy', got '{data.get('status')}'"
    assert str(data.get("backend_port")) == "8025", f"Expected backend_port 8025, got '{data.get('backend_port')}'"
    assert data == {"status": "healthy", "backend_port": 8025} or data == {"status": "healthy", "backend_port": "8025"}, \
        f"Health response contains unexpected payload: {data}"

    token = uuid.uuid4().hex
    direct_sender = f"direct-{token}@verifier.test"
    direct_recipient = f"direct-recipient-{token}@local"
    direct_body = f"DIRECT-BODY-{token}"
    proxy_sender = f"proxy-{token}@verifier.test"
    proxy_recipient = f"proxy-recipient-{token}@local"
    proxy_body = f"PROXY-BODY-{token}"

    # Port 8025 must itself be a functioning SMTP backend.
    send_message(8025, direct_sender, direct_recipient, direct_body)

    # Hold a proxy connection open and verify the proxy process establishes a
    # corresponding TCP connection to the backend port.
    sock = socket.create_connection(("127.0.0.1", 2525), timeout=5)
    try:
        sock.settimeout(5)
        greeting = sock.recv(1024)
        assert greeting.startswith(b"220"), f"Proxy did not relay an SMTP greeting: {greeting!r}"
        time.sleep(0.2)
        proxy_tree = descendants(proxy_pid)
        owned = set()
        for pid in proxy_tree:
            owned.update(pid_socket_inodes(pid))
        forwarded = any(
            entry["state"] == "01"
            and entry["remote_port"] == 8025
            and entry["remote_addr"] == "0100007F"
            and entry["inode"] in owned
            for entry in tcp_entries()
        )
        assert forwarded, "The port 2525 proxy did not open a TCP connection to 127.0.0.1:8025."
    finally:
        sock.close()

    send_message(2525, proxy_sender, proxy_recipient, proxy_body)
    time.sleep(1)

    assert os.path.exists(LOG_PATH), f"Mail sink log {LOG_PATH} does not exist."
    with open(LOG_PATH, "r", errors="replace") as f:
        log_content = f.read()
    for expected in (
        direct_sender, direct_recipient, direct_body,
        proxy_sender, proxy_recipient, proxy_body,
    ):
        assert expected in log_content, f"Fresh SMTP value {expected!r} not found in mail_sink.log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
